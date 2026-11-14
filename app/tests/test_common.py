import pytest
from sqlalchemy import func, select

from cloudjudge import cli
from cloudjudge.common import db
from cloudjudge.common.config import Config, parse_env_file
from cloudjudge.common.problems import ProblemError, build_tests_zip, read_tests_zip


def test_env_file_parsing(tmp_path):
    f = tmp_path / "cj.env"
    f.write_text("# comment\nCJ_ROLE=worker\nDB_PORT=3307\nSTORAGE_AUTH=appcred            # local dev: tempauth\n"
                 "MQ_PASSWORD=\"abc\"\n\nDB_REPLICA_HOST=\n")
    env = parse_env_file(str(f))
    cfg = Config.from_env(env | {"DB_PRIMARY_HOST": "10.0.3.10"})
    assert cfg.role == "worker" and cfg.db_port == 3307 and cfg.storage_auth == "appcred"
    assert cfg.mq_password == "abc"
    assert cfg.db_replica_host == "10.0.3.10"   # rỗng → dùng primary


def test_tests_zip_roundtrip_and_validation():
    tests = [(b"1 2\n", b"3\n"), (b"5 5\n", b"10\n")]
    assert read_tests_zip(build_tests_zip(tests)) == tests
    with pytest.raises(ProblemError):
        read_tests_zip(b"not a zip")
    import io
    import zipfile
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr("1.in", "x")
        z.writestr("1.out", "y")
        z.writestr("3.in", "x")
    with pytest.raises(ProblemError):
        read_tests_zip(buf.getvalue())


def test_seed_is_idempotent(cfg, seeded, storage):
    cli.main(["seed", "--password", "other-pass", "--loadtest-token", "t" * 64], cfg=cfg, engine=seeded, storage=storage)
    with seeded.connect() as conn:
        assert conn.execute(select(func.count()).select_from(db.users)).scalar() == 7
        assert conn.execute(select(func.count()).select_from(db.problems)).scalar() == 2
        tc = dict(conn.execute(select(db.problems.c.slug, db.problems.c.test_count)).all())
        token = conn.execute(select(db.users.c.api_token).where(db.users.c.username == "loadtest")).scalar()
    assert tc == {"a-plus-b": 6, "slow-sum": 4}
    assert token == "t" * 64
    assert (cfg.swift_testcases, "slow-sum/tests.zip") in storage.objects
