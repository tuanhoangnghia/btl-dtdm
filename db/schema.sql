-- CloudJudge schema v1 (chủ sở hữu: C). Mọi thay đổi ghi vào docs/CONTRACT.md mục Nhật ký.
CREATE DATABASE IF NOT EXISTS cloudjudge CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE cloudjudge;

CREATE TABLE IF NOT EXISTS users (
  id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  username      VARCHAR(64)  NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  role          ENUM('student','teacher') NOT NULL DEFAULT 'student',
  api_token     CHAR(64) NULL UNIQUE,
  created_at    DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS problems (
  id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  slug             VARCHAR(64)  NOT NULL UNIQUE,
  title            VARCHAR(200) NOT NULL,
  statement_md     TEXT NOT NULL,
  time_limit_ms    INT UNSIGNED NOT NULL DEFAULT 2000,
  memory_mb        INT UNSIGNED NOT NULL DEFAULT 256,
  testcases_object VARCHAR(255) NOT NULL,          -- vd: a-plus-b/tests.zip (container testcases)
  test_count       SMALLINT UNSIGNED NOT NULL,
  created_by       INT UNSIGNED NOT NULL,
  created_at       DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  CONSTRAINT fk_problems_user FOREIGN KEY (created_by) REFERENCES users(id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS submissions (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid          CHAR(36) NOT NULL UNIQUE,
  user_id       INT UNSIGNED NOT NULL,
  problem_id    INT UNSIGNED NOT NULL,
  language      ENUM('cpp','python') NOT NULL,
  source_object VARCHAR(255) NOT NULL,             -- vd: <uuid>/main.cpp (container submissions)
  status        ENUM('PENDING','RUNNING','ACCEPTED','WRONG_ANSWER','TIME_LIMIT',
                     'RUNTIME_ERROR','COMPILE_ERROR','SYSTEM_ERROR') NOT NULL DEFAULT 'PENDING',
  score         TINYINT UNSIGNED NULL,             -- 0..100
  passed        SMALLINT UNSIGNED NULL,
  total         SMALLINT UNSIGNED NULL,
  runtime_ms    INT UNSIGNED NULL,                 -- tổng thời gian chạy các test
  message       VARCHAR(2000) NULL,                -- lỗi biên dịch / ghi chú ngắn
  worker_host   VARCHAR(64) NULL,
  created_at    DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  started_at    DATETIME(3) NULL,
  finished_at   DATETIME(3) NULL,
  CONSTRAINT fk_sub_user    FOREIGN KEY (user_id)    REFERENCES users(id),
  CONSTRAINT fk_sub_problem FOREIGN KEY (problem_id) REFERENCES problems(id),
  INDEX idx_status_created (status, created_at),
  INDEX idx_user_created (user_id, created_at),
  INDEX idx_problem_user (problem_id, user_id)
) ENGINE=InnoDB;
