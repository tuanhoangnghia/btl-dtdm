# CloudJudge – Kế hoạch triển khai chi tiết (runbook)

> Bài tập lớn INT3319 3 – Điện toán đám mây. Nhóm: Hoàng Nghĩa Tuấn (23020877), Nguyễn Minh Trọng (23020893), Trần Văn Phường (23020859).
> Lập ngày 28/10/2026. **Hạn nộp báo cáo + mã nguồn + video: 09/11/2026. Bảo vệ: 16/11/2026.**
> Nguồn: `Bài tập lớn cuối kỳ - Hướng dẫn đề xuất dự án - Student-1.pdf` và `De_xuat_CloudJudge_ban_nop (2) (1).docx` trong cùng thư mục.

---

## 0. Cách dùng file này

- File này là **nguồn sự thật duy nhất** khi triển khai. Mỗi phiên làm việc: đọc mục **17. Trạng thái** để biết đang ở đâu, làm tiếp phase kế tiếp, xong thì tích `[x]` và ghi chú (IP, ID, lỗi gặp phải) vào mục đó.
- Mọi thao tác hạ tầng GCP làm bằng **gcloud CLI** từ laptop Windows (Git Bash). Mọi thao tác OpenStack làm qua **SSH vào `os-controller`**.
- Quy ước cho Claude ở phiên sau:
  - Chạy `gcloud` qua Bash tool (Git Bash). Lệnh tương tác (`gcloud auth login`) thì nhờ người dùng tự gõ bằng `! gcloud auth login` trong ô chat.
  - Không dùng `gcloud compute ssh` (trên Windows nó gọi PuTTY). Dùng `ssh` OpenSSH với key riêng và `~/.ssh/config` (mục 4.3).
  - Lệnh chạy lâu (`kolla-ansible deploy`, build image): chạy trong `tmux` trên controller, rồi theo dõi log bằng lệnh `tail` riêng; không giữ phiên SSH mở 1 tiếng.
  - **Hỏi người dùng trước** khi: tạo/xóa VM GCP, xóa disk/snapshot, `kolla-ansible destroy`, `openstack stack delete` stack dữ liệu.
  - **Không bao giờ** commit: `passwords.yml`, `clouds.yaml`, `secrets.env`, private key, Tailscale auth key, mật khẩu Gmail.
- Biến dùng chung (đặt ở đầu mỗi phiên Git Bash):

```bash
export PROJECT_ID="cloudjudge-<hậu-tố-duy-nhất>"   # ghi giá trị thật vào mục 17
export REGION="asia-southeast1"
export ZONE_A="asia-southeast1-a"
export ZONE_B="asia-southeast1-b"
```

---

## 1. Tín dụng GCP có đủ không?

Tài khoản đang có: **₫7.730.577 (≈ 297 USD, tính 1 USD ≈ 26.000 đ), còn 56 ngày** → hết hạn khoảng 23/12/2026, **sau** ngày bảo vệ. Đủ dùng, **với điều kiện tắt máy khi không làm**.

| Hạng mục (Singapore, giá ước tính) | Đơn giá | Ghi chú |
|---|---|---|
| os-controller n2-highmem-4 | ≈ 0,32 USD/giờ | chỉ tính khi máy chạy |
| 2 × n2-highmem-2 | ≈ 0,16 USD/giờ/máy | |
| IP public (1 static + 2 ephemeral) | ≈ 0,015 USD/giờ | static IP vẫn tính ~0,01 USD/giờ khi máy tắt |
| **Cụm chạy** | **≈ 0,66 USD/giờ ≈ 17.000 đ/giờ** | |
| Đĩa pd-balanced 340 GB | ≈ 0,11 USD/GB-tháng | tính cả khi tắt máy: ≈ 1,25 USD/ngày |
| Snapshot (~150 GB) | ≈ 0,065 USD/GB-tháng | |

| Kịch bản (29/10 → 16/11) | Chi phí | Kết luận |
|---|---|---|
| Tắt máy khi không dùng, ~180 giờ chạy | ≈ 119 + 25 (đĩa) + 5 (snapshot) + 3 (IP) ≈ **150 USD ≈ 3,9 triệu đ** | ✅ còn dư ~3,8 triệu |
| Chạy 24/7 suốt 19 ngày (456 giờ) | ≈ 300 + 33 ≈ **333 USD** | ❌ **hết tín dụng trước ngày bảo vệ** |

**Quy tắc bắt buộc:**
1. Tổng giờ chạy cụm **≤ 300 giờ**. Hết buổi làm là chạy `scripts/gcp-down.sh`.
2. Đặt **budget alert** 50% / 75% / 90% (Phase 1).
3. Free trial giới hạn **8 vCPU chạy đồng thời** trên toàn tài khoản; cụm dùng đúng 8. **Không tạo thêm VM GCP nào khác** (VM build image chạy *bên trong* OpenStack).
4. Không cần nâng cấp lên tài khoản trả phí. Nếu bị chặn quota thì báo nhóm trước khi nâng cấp, vì nâng cấp sẽ trừ tiền thẻ khi hết tín dụng.

---

## 2. Quyết định kỹ thuật đã chốt (và điểm khác so với bản đề xuất)

Các mục đánh dấu **(≠ đề xuất)** phải nêu lý do trong báo cáo cuối, mục "Lý giải lựa chọn công nghệ".

| # | Quyết định | Lý do |
|---|---|---|
| D1 | **Kolla-Ansible 2024.2 (Dalmatian, bản 19.x)** trên Ubuntu 24.04 **(≠ đề xuất: không ghi phiên bản)** | Release note 2025.1 ghi rõ *"Support for deploying Swift has been removed"*. 2024.2 là bản cuối còn Swift **và** hỗ trợ Ubuntu Noble 24.04. Nhánh 2024.2 có thể đã sang trạng thái *unmaintained*, chấp nhận được với bài tập |
| D2 | **Neutron ML2/Open vSwitch** (không dùng OVN) **(≠ đề xuất)** | Chế độ `octavia_network_type: "tenant"` của Kolla (tự tạo mạng quản lý amphora, không cần VLAN vật lý) **chỉ hỗ trợ OVS**. Trên GCE không có VLAN/L2 thật nên đây là con đường khả thi nhất cho Octavia |
| D3 | Phương án dự phòng khi Octavia lỗi: **topology SINGLE**, rồi mới đến **2 VM HAProxy + keepalived** **(≠ đề xuất: "OVN provider")** | Do D2 nên OVN provider không dùng được. Ghi rõ trong báo cáo |
| D4 | Mạng external **giả** bằng cặp veth trên controller (`veth-host` 172.24.4.1/24 ↔ `veth-ex` gắn vào `br-ex`); controller NAT ra Internet và DNAT cổng 80 public vào floating IP của LB | GCE không cho L2/ARP tự do và không cấp được dải IP public cho floating IP |
| D5 | VPC GCE **MTU 1500** → mạng tenant VXLAN MTU 1450 (Neutron tự tính) | Tránh lỗi MTU ngầm |
| D6 | Ảo hóa lồng: GCE `--enable-nested-virtualization`, Nova `virt_type=kvm`, `cpu_mode=host-passthrough` | Không có KVM thì máy ảo boot 5–10 phút → demo autoscale thất bại |
| D7 | AZ: host aggregate `az1` = os-compute-1 (zone a), `az2` = os-compute-2 (zone b). Rải máy bằng **ServerGroup soft-anti-affinity** | Heat ASG không tự rải theo AZ. Mỗi AZ có 1 host nên anti-affinity theo host tương đương anti-affinity theo AZ |
| D8 | **Một golden image `cj-base-v1`** cho mọi vai trò (web, worker, mysql, rabbitmq, monitor, bastion). Vai trò do cloud-init chọn; code ứng dụng tải từ Swift container `releases` khi boot | Build image 1 lần. Sửa code chỉ cần upload tarball mới rồi thay máy. Máy scale out boot nhanh |
| D9 | MySQL, RabbitMQ, Prometheus/Alertmanager/Grafana chạy bằng **Docker container trong VM**. Web và worker chạy **systemd + venv** | Container hóa phần hạ tầng cho dễ dựng. Worker cần gọi `docker run` trực tiếp để tạo sandbox |
| D10 | **4 danh tính Keystone**: `cj-web`, `cj-worker`, `cj-monitor` và thêm `cj-backup` **(≠ đề xuất: 3)** | Quyền tối thiểu: chỉ backup mới được ghi vào container `backups` |
| D11 | Alertmanager gọi thẳng **`alarm_url`** (URL đã ký sẵn của heat-api-cfn) của `OS::Heat::ScalingPolicy`. Dự phòng: adapter Flask ~50 dòng gọi `openstack stack resource signal` | Không cần Aodh/Ceilometer. Máy monitor không giữ credential có quyền Heat |
| D12 | Truy cập quản trị: Tailscale trên **controller** (quảng bá 10.10.0.0/24 và 172.24.4.0/24) và trên **bastion** (quảng bá 10.0.2.0/24 và 10.0.3.0/24) | SSH public chỉ mở cho IP của mình trong lúc dựng, sau đó đóng hẳn |
| D13 | Region `asia-southeast1` (Singapore) | Độ trễ thấp khi demo từ Việt Nam, khớp đơn giá trong đề xuất. (`us-central1` rẻ hơn ~20% nhưng trễ ~200 ms) |

---

## 3. Thông số cố định

### 3.1. Máy GCE

| Tên | Zone | Loại | IP nội bộ | IP public | Đĩa | Vai trò Kolla |
|---|---|---|---|---|---|---|
| os-controller | asia-southeast1-a | n2-highmem-4 (4 vCPU, 32 GB) | 10.10.0.10 | static `cj-ctl-ip` | boot 100 GB + `cinder` 50 GB + `swift` 30 GB | control, network, storage, monitoring, deployment |
| os-compute-1 | asia-southeast1-a | n2-highmem-2 (2 vCPU, 16 GB) | 10.10.0.11 | ephemeral (chỉ để ra Internet) | boot 80 GB | compute, AZ `az1` |
| os-compute-2 | asia-southeast1-b | n2-highmem-2 | 10.10.0.12 | ephemeral | boot 80 GB | compute, AZ `az2` |

### 3.2. Mạng OpenStack (project `cloudjudge`)

| Mạng | CIDR | Pool DHCP | Floating IP? | Thành phần |
|---|---|---|---|---|
| ext-net (flat, physnet1) | 172.24.4.0/24, gw 172.24.4.1 | .10–.250 | – | mạng external giả |
| net-public | 10.0.1.0/24 | .50–.200 | có | Octavia VIP, bastion |
| net-app | 10.0.2.0/24 | .50–.200 | **không** | rabbitmq 10.0.2.10, monitor 10.0.2.11, web/worker lấy DHCP |
| net-data | 10.0.3.0/24 | .50–.200 | **không** | mysql-primary 10.0.3.10 (az1), mysql-replica 10.0.3.11 (az2) |
| lb-mgmt-net | (Kolla tự tạo, project `service`) | | | amphora |

Router `cj-router`: gateway là ext-net (SNAT), có interface vào cả 3 subnet.

### 3.3. Security group (tạo trong stack `cj-net`)

| SG | Ingress cho phép |
|---|---|
| sg-bastion | 22/tcp từ 172.24.4.1/32 (cứu hộ từ controller) |
| sg-web | 8000/tcp từ 10.0.1.0/24 (amphora, đi qua router); 22 từ sg-bastion; 8000 + 9100 từ sg-monitor |
| sg-worker | 22 từ sg-bastion; 9100 từ sg-monitor |
| sg-mq | 5672 từ sg-web và sg-worker; 15692 từ sg-monitor; 22 từ sg-bastion |
| sg-db | 3306 từ sg-web, sg-worker, sg-db (replication); 9104 + 9100 từ sg-monitor; 22 từ sg-bastion |
| sg-monitor | 3000, 9090, 9093 từ sg-bastion (Tailscale); 22 từ sg-bastion |

> Pool member của Octavia **không khai báo `subnet`**. Khi đó amphora đi tới web **qua router từ địa chỉ 10.0.1.x**, nên sg-web chỉ mở 8000 cho 10.0.1.0/24. Worker (10.0.2.x) gọi thẳng web sẽ **bị chặn**, đúng như hạng mục 2 cần chứng minh.

### 3.4. Flavor

| Flavor | vCPU / RAM / Disk | Dùng cho |
|---|---|---|
| cj.tiny | 1 / 512 MB / 10 GB | bastion |
| cj.small | 1 / 1024 MB / 10 GB | web, rabbitmq |
| cj.medium | 1 / 2048 MB / 20 GB | worker, mysql ×2, monitor, builder |
| amphora | 1 / 1024 MB / 5 GB | Kolla tự tạo |

Tải tối đa: 2 amphora + 3 web + 3 worker + 2 mysql + rabbit + monitor + bastion ≈ **18,5 GB RAM / 14 vCPU ảo** trên 32 GB / 4 vCPU vật lý. Vì vậy cần đặt `cpu_allocation_ratio = 8.0`.

### 3.5. Danh tính Keystone

| User | Role trên project `cloudjudge` | Quyền Swift | Dùng ở |
|---|---|---|---|
| cj-web | member | toàn quyền (member là operator role) | web |
| cj-worker | reader | chỉ đọc qua ACL `submissions`, `testcases`, `releases` → **xóa bị 403** | worker |
| cj-monitor | reader | không | Prometheus `openstack_sd` (liệt kê server) |
| cj-backup | reader | ghi qua ACL `backups`, đọc `releases` | cron trên mysql-primary |

Mỗi user có **1 application credential**, truyền vào VM qua tham số `hidden: true` của Heat. Tương đương IAM role / instance profile.

---

## 4. Phase 0 – Chuẩn bị laptop (≈ 30 phút)

### 4.1. Công cụ
- [ ] Google Cloud SDK cho Windows: `gcloud version`
- [ ] Git, OpenSSH: `ssh -V` (có sẵn trong Git Bash)
- [ ] Tailscale client cho Windows; tạo tài khoản Tailscale, mời 2 bạn cùng nhóm
- [ ] Repo GitHub **private** `cloudjudge`, mời 3 thành viên
- [ ] `gitleaks` (tải bản Windows) và `pre-commit` (`pip install pre-commit`)

### 4.2. Đăng nhập gcloud (người dùng tự gõ)
```
! gcloud auth login
! gcloud auth application-default login     # không bắt buộc
```

### 4.3. SSH key và cấu hình
```bash
ssh-keygen -t ed25519 -N "" -C "cj@laptop" -f ~/.ssh/cloudjudge
echo "cj:$(cat ~/.ssh/cloudjudge.pub)" > ~/.ssh/cj-ssh-keys.txt     # định dạng metadata GCE: user:key
```
Thêm vào `~/.ssh/config` (điền `CTL_IP` sau Phase 1):
```
Host cj-ctl
  HostName <CTL_IP>
  User cj
  IdentityFile ~/.ssh/cloudjudge
  StrictHostKeyChecking accept-new
  ServerAliveInterval 30
Host cj-c1
  HostName 10.10.0.11
  User cj
  IdentityFile ~/.ssh/cloudjudge
  ProxyJump cj-ctl
Host cj-c2
  HostName 10.10.0.12
  User cj
  IdentityFile ~/.ssh/cloudjudge
  ProxyJump cj-ctl
```

### 4.4. Khung repo
```
cloudjudge/
├─ .gitignore              # secrets/, *.pem, clouds.yaml, passwords.yml, *.env (trừ *.env.example)
├─ .pre-commit-config.yaml # hook gitleaks
├─ README.md               # cách dựng lại từ đầu
├─ infra/
│  ├─ gcp/                 # 00-vars.sh, 10-project.sh, 20-network.sh, 30-vms.sh, gcp-up.sh, gcp-down.sh, snapshot.sh, update-ssh-ip.sh
│  ├─ host/                # prepare-all.sh, prepare-controller.sh, cj-nat.sh, cj-nat.service, 25-veth-*.netdev/.network
│  ├─ kolla/               # globals.yml, multinode, config/nova.conf, config/octavia.conf, swift-rings.sh
│  └─ bootstrap/           # 10-az-flavor-image.sh, 20-extnet.sh, 30-project-users.sh, 40-appcreds.sh, 50-swift-acl.sh, 60-amphora.sh
├─ image/                  # build-cj-base.sh (user-data cho VM builder), sandbox/Dockerfile
├─ heat/                   # cj-net.yaml, cj-data.yaml, cj-app.yaml, cj-mon.yaml, web_member.yaml, worker.yaml, env/*.yaml
├─ app/                    # cloudjudge/{common,web,worker}, deploy/{install.sh,systemd/*.service}, requirements.txt, docker-compose.dev.yml
├─ monitoring/             # prometheus.yml.tpl, rules.yml, alertmanager.yml.tpl, grafana/{datasource.yml,dashboard.json}, docker-compose.yml
├─ scripts/                # deploy-stacks.sh, release.sh, loadtest.py, demo-checks.sh, cj-health.sh, backup-mysql.sh
└─ docs/                   # report/, evidence/ (ảnh minh chứng), cost.xlsx, architecture.png
```
Trên controller, file bí mật nằm ở `~/secrets/secrets.env` (chmod 600), **không** nằm trong repo. Một bản sao giữ trong trình quản lý mật khẩu của nhóm.

---

## 5. Phase 1 – Hạ tầng GCP bằng gcloud (≈ 1 giờ) — người phụ trách: A

### 5.1. Project, billing, API, ngân sách
```bash
gcloud projects create "$PROJECT_ID" --name="CloudJudge"
gcloud billing accounts list                                  # lấy BILLING_ID (tài khoản Free Trial)
export BILLING_ID="XXXXXX-XXXXXX-XXXXXX"
gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ID"
gcloud config set project "$PROJECT_ID"
gcloud config set compute/region "$REGION"
gcloud services enable compute.googleapis.com billingbudgets.googleapis.com

# Ngân sách theo VND (đơn vị tiền của tài khoản)
gcloud billing budgets create --billing-account="$BILLING_ID" \
  --display-name="cj-budget" --budget-amount=7700000VND \
  --threshold-rule=percent=0.5 --threshold-rule=percent=0.75 --threshold-rule=percent=0.9
```

### 5.2. Kiểm tra quota (phải đủ trước khi tạo máy)
```bash
gcloud compute project-info describe --format="table(quotas.metric,quotas.limit,quotas.usage)" | grep -E "CPUS_ALL_REGIONS"
gcloud compute regions describe "$REGION" --format="table(quotas.metric,quotas.limit,quotas.usage)" \
  | grep -E "^(CPUS|N2_CPUS|DISKS_TOTAL_GB|SSD_TOTAL_GB|IN_USE_ADDRESSES|STATIC_ADDRESSES) "
```
Cần tối thiểu: CPUS_ALL_REGIONS ≥ 8, N2_CPUS ≥ 8, DISKS_TOTAL_GB ≥ 340, IN_USE_ADDRESSES ≥ 3, STATIC_ADDRESSES ≥ 1.

### 5.3. VPC, firewall, IP tĩnh
```bash
gcloud compute networks create cj-vpc --subnet-mode=custom --mtu=1500
gcloud compute networks subnets create cj-subnet --network=cj-vpc --region="$REGION" --range=10.10.0.0/24

MY_IP=$(curl -s https://ifconfig.me)
gcloud compute firewall-rules create cj-allow-internal --network=cj-vpc \
  --allow=tcp,udp,icmp --source-ranges=10.10.0.0/24
gcloud compute firewall-rules create cj-allow-ssh-admin --network=cj-vpc \
  --allow=tcp:22 --source-ranges="${MY_IP}/32" --target-tags=os-controller
gcloud compute firewall-rules create cj-allow-http --network=cj-vpc \
  --allow=tcp:80 --source-ranges=0.0.0.0/0 --target-tags=os-controller
gcloud compute firewall-rules create cj-allow-tailscale --network=cj-vpc \
  --allow=udp:41641 --source-ranges=0.0.0.0/0 --target-tags=os-controller

gcloud compute addresses create cj-ctl-ip --region="$REGION"
CTL_IP=$(gcloud compute addresses describe cj-ctl-ip --region="$REGION" --format="value(address)")
echo "CTL_IP=$CTL_IP"     # ghi vào mục 17 và ~/.ssh/config
```
`infra/gcp/update-ssh-ip.sh` cập nhật rule SSH khi IP nhà thay đổi:
`gcloud compute firewall-rules update cj-allow-ssh-admin --source-ranges="$(curl -s https://ifconfig.me)/32"`.

### 5.4. SSH key vào metadata project
```bash
gcloud compute project-info add-metadata --metadata-from-file=ssh-keys="$HOME/.ssh/cj-ssh-keys.txt"
```
Lệnh này **ghi đè** giá trị `ssh-keys`. Mỗi lần thêm key thì sửa file txt (nối thêm dòng) rồi chạy lại.

### 5.5. Tạo 3 máy (bật nested virtualization)
```bash
COMMON="--image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud \
  --boot-disk-type=pd-balanced --enable-nested-virtualization --metadata=enable-oslogin=FALSE"

gcloud compute instances create os-controller --zone="$ZONE_A" --machine-type=n2-highmem-4 $COMMON \
  --boot-disk-size=100GB \
  --network-interface=subnet=cj-subnet,private-network-ip=10.10.0.10,address="$CTL_IP" \
  --create-disk=name=os-controller-cinder,size=50GB,type=pd-balanced,device-name=cinder,auto-delete=yes \
  --create-disk=name=os-controller-swift,size=30GB,type=pd-balanced,device-name=swift,auto-delete=yes \
  --tags=os-controller

gcloud compute instances create os-compute-1 --zone="$ZONE_A" --machine-type=n2-highmem-2 $COMMON \
  --boot-disk-size=80GB --network-interface=subnet=cj-subnet,private-network-ip=10.10.0.11 --tags=os-compute

gcloud compute instances create os-compute-2 --zone="$ZONE_B" --machine-type=n2-highmem-2 $COMMON \
  --boot-disk-size=80GB --network-interface=subnet=cj-subnet,private-network-ip=10.10.0.12 --tags=os-compute
```

### 5.6. Kiểm tra (✅ điều kiện qua phase)
```bash
ssh cj-ctl 'hostname; ip -br a; grep -cw vmx /proc/cpuinfo; ls -l /dev/kvm; lsblk'
ssh cj-c1  'hostname; grep -cw vmx /proc/cpuinfo; ls -l /dev/kvm'
ssh cj-c2  'hostname; grep -cw vmx /proc/cpuinfo; ls -l /dev/kvm'
```
- Số `vmx` > 0 và có `/dev/kvm` trên **cả 3 máy**. Nếu thiếu: `gcloud compute instances describe <vm> --zone ... --format="value(advancedMachineFeatures)"`. Nested chỉ bật được lúc tạo máy, nên phải xóa và tạo lại.
- Interface là `ens4` (nếu khác thì sửa `network_interface` trong globals.yml).
- Thấy `/dev/disk/by-id/google-cinder` và `/dev/disk/by-id/google-swift` trên controller.

### 5.7. Script bật/tắt (viết ngay, dùng hằng ngày)
```bash
# infra/gcp/gcp-down.sh
gcloud compute instances stop os-compute-1 os-controller --zone="$ZONE_A" --async
gcloud compute instances stop os-compute-2 --zone="$ZONE_B" --async
# infra/gcp/gcp-up.sh  (bật controller trước, sau đó compute)
gcloud compute instances start os-controller --zone="$ZONE_A"
gcloud compute instances start os-compute-1 --zone="$ZONE_A" --async
gcloud compute instances start os-compute-2 --zone="$ZONE_B" --async
```

---

## 6. Phase 2 – Chuẩn bị host (≈ 45 phút) — A

### 6.1. Trên cả 3 máy (`infra/host/prepare-all.sh`, chạy bằng `ssh cj-ctl 'sudo bash -s' < infra/host/prepare-all.sh`, tương tự với c1, c2)
```bash
set -eux
apt-get update && apt-get -y upgrade
apt-get install -y python3-venv python3-dev git gcc libffi-dev libssl-dev libdbus-glib-1-dev tmux jq xfsprogs lvm2
systemctl disable --now unattended-upgrades || true     # tránh tự cập nhật/khởi động lại giữa buổi demo
timedatectl set-timezone Asia/Ho_Chi_Minh
```

### 6.2. Riêng controller (`infra/host/prepare-controller.sh`)
**a) Cặp veth cho mạng external giả** (bền qua reboot nhờ systemd-networkd):
```ini
# /etc/systemd/network/25-veth.netdev
[NetDev]
Name=veth-host
Kind=veth
[Peer]
Name=veth-ex

# /etc/systemd/network/25-veth-host.network
[Match]
Name=veth-host
[Network]
Address=172.24.4.1/24
ConfigureWithoutCarrier=yes

# /etc/systemd/network/25-veth-ex.network
[Match]
Name=veth-ex
[Network]
LinkLocalAddressing=no
ConfigureWithoutCarrier=yes
```
Áp dụng: `networkctl reload && ip link set veth-ex up && ip -br a show veth-host`.

**b) NAT/DNAT** (`/usr/local/sbin/cj-nat.sh` + `cj-nat.service` dạng oneshot, `After=network-online.target`):
```bash
#!/bin/bash
sysctl -w net.ipv4.ip_forward=1
iptables -P FORWARD ACCEPT
ip link set veth-ex up
# Tenant (đã SNAT qua router → 172.24.4.x) ra Internet
iptables -t nat -C POSTROUTING -s 172.24.4.0/24 ! -d 172.24.4.0/24 -o ens4 -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -s 172.24.4.0/24 ! -d 172.24.4.0/24 -o ens4 -j MASQUERADE
# Cổng 80 public → floating IP của LB (điền sau Phase 7 vào /etc/cloudjudge/lb_fip)
if [ -s /etc/cloudjudge/lb_fip ]; then
  FIP=$(cat /etc/cloudjudge/lb_fip)
  iptables -t nat -C PREROUTING -i ens4 -p tcp --dport 80 -j DNAT --to-destination "$FIP:80" 2>/dev/null \
    || iptables -t nat -A PREROUTING -i ens4 -p tcp --dport 80 -j DNAT --to-destination "$FIP:80"
fi
```
DNAT chỉ áp cho gói vào từ `ens4` (Internet). Horizon của Kolla vẫn ở `10.10.0.10:80`, truy cập qua Tailscale.

**c) Đĩa Cinder (LVM)**
```bash
pvcreate /dev/disk/by-id/google-cinder
vgcreate cinder-volumes /dev/disk/by-id/google-cinder
```

**d) Đĩa Swift**
```bash
parted /dev/disk/by-id/google-swift -s -- mklabel gpt mkpart KOLLA_SWIFT_DATA 1 -1
sleep 2
mkfs.xfs -f -L d0 /dev/disk/by-id/google-swift-part1
```

**e) Tailscale**
```bash
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --authkey="$TS_CTL_KEY" --hostname=cj-controller --advertise-routes=10.10.0.0/24,172.24.4.0/24
```
Sau đó vào Tailscale admin console để **duyệt** 2 route. Từ laptop kiểm tra `ping 10.10.0.10`.

**f) Key để Kolla SSH sang các compute**
```bash
ssh cj-ctl 'ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519 && cat ~/.ssh/id_ed25519.pub'
# Trên laptop: nối thêm dòng "cj:<pubkey vừa in>" vào ~/.ssh/cj-ssh-keys.txt, rồi chạy lại lệnh ở 5.4
ssh cj-ctl 'sleep 60; ssh -o StrictHostKeyChecking=accept-new 10.10.0.11 hostname; ssh -o StrictHostKeyChecking=accept-new 10.10.0.12 hostname; ssh -o StrictHostKeyChecking=accept-new 10.10.0.10 hostname'
```

✅ **Điều kiện qua phase:** `veth-host` có 172.24.4.1; `vgs` thấy `cinder-volumes`; `blkid` thấy label `d0` / `KOLLA_SWIFT_DATA`; controller SSH được sang cả 3 IP không cần mật khẩu.

---

## 7. Phase 3 – Cài OpenStack bằng Kolla-Ansible 2024.2 (≈ 2–3 giờ, phần lớn là chờ) — A

### 7.1. Cài Kolla-Ansible (trên controller, user `cj`)
```bash
python3 -m venv ~/kolla-venv && source ~/kolla-venv/bin/activate
pip install -U pip
pip install 'ansible-core>=2.16,<2.18'
pip install 'kolla-ansible>=19,<20'          # 19.x = 2024.2 Dalmatian
sudo mkdir -p /etc/kolla && sudo chown cj:cj /etc/kolla
cp -r ~/kolla-venv/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/
kolla-ansible install-deps
kolla-genpwd                                  # sinh /etc/kolla/passwords.yml — KHÔNG commit
```
> ⚠️ Nếu `install-deps` lỗi vì không tìm thấy nhánh `stable/2024.2` của `ansible-collection-kolla` (nhánh đã đổi tên khi sang unmaintained), hãy sửa `~/kolla-venv/share/kolla-ansible/requirements.yml`: đổi `version` thành `unmaintained/2024.2` hoặc tag `2024.2-eol`, rồi chạy lại.

### 7.2. Inventory `infra/kolla/multinode`
Copy từ `~/kolla-venv/share/kolla-ansible/ansible/inventory/multinode`, **chỉ sửa các nhóm đầu file**, giữ nguyên phần còn lại:
```ini
[control]
os-controller ansible_host=10.10.0.10 ansible_user=cj ansible_become=true

[network]
os-controller

[compute]
os-compute-1 ansible_host=10.10.0.11 ansible_user=cj ansible_become=true
os-compute-2 ansible_host=10.10.0.12 ansible_user=cj ansible_become=true

[monitoring]
os-controller

[storage]
os-controller

[deployment]
localhost ansible_connection=local
```

### 7.3. `/etc/kolla/globals.yml` (lưu bản sao ở `infra/kolla/globals.yml`)
```yaml
kolla_base_distro: "ubuntu"
openstack_release: "2024.2"
kolla_internal_vip_address: "10.10.0.10"     # 1 controller, không dùng VIP/keepalived
network_interface: "ens4"
neutron_external_interface: "veth-ex"
neutron_plugin_agent: "openvswitch"
enable_haproxy: "no"
nova_compute_virt_type: "kvm"

enable_cinder: "yes"
enable_cinder_backend_lvm: "yes"
cinder_volume_group: "cinder-volumes"
enable_cinder_backup: "no"

enable_swift: "yes"
enable_heat: "yes"
enable_horizon: "yes"

enable_octavia: "yes"
octavia_network_type: "tenant"
octavia_auto_configure: "yes"
enable_redis: "yes"                           # Octavia jobboard cần Redis; nhẹ, bật cho chắc

enable_fluentd: "no"                          # tiết kiệm RAM/đĩa
```

### 7.4. Cấu hình ghi đè (`/etc/kolla/config/`, lưu bản sao ở `infra/kolla/config/`)
```ini
# /etc/kolla/config/nova.conf
[DEFAULT]
cpu_allocation_ratio = 8.0
ram_allocation_ratio = 1.0
reserved_host_memory_mb = 2048
resume_guests_state_on_host_boot = true
[libvirt]
cpu_mode = host-passthrough

# /etc/kolla/config/octavia.conf
[controller_worker]
loadbalancer_topology = ACTIVE_STANDBY
amp_active_retries = 100
amp_active_wait_sec = 10
[nova]
enable_anti_affinity = True
```

### 7.5. Swift ring (1 node, 1 đĩa, 1 bản sao) — `infra/kolla/swift-rings.sh`
Chạy **sau** `bootstrap-servers` (lúc đó máy đã có Docker):
```bash
IMG="quay.io/openstack.kolla/swift-base:2024.2-ubuntu-noble"   # nếu pull lỗi thì tra tag đúng trên quay.io/openstack.kolla/swift-base
sudo docker pull "$IMG"
sudo mkdir -p /etc/kolla/config/swift
run(){ sudo docker run --rm -v /etc/kolla/config/swift/:/etc/kolla/config/swift/ "$IMG" "$@"; }
for spec in object:6000 account:6001 container:6002; do
  ring=${spec%%:*}; port=${spec##*:}
  run swift-ring-builder /etc/kolla/config/swift/$ring.builder create 10 1 1
  run swift-ring-builder /etc/kolla/config/swift/$ring.builder add r1z1-10.10.0.10:$port/d0 1
  run swift-ring-builder /etc/kolla/config/swift/$ring.builder rebalance
done
ls -l /etc/kolla/config/swift/      # phải có *.builder và *.ring.gz
```

### 7.6. Triển khai (chạy trong tmux, ghi log)
```bash
cd ~ && source ~/kolla-venv/bin/activate
INV=~/cloudjudge/infra/kolla/multinode
kolla-ansible bootstrap-servers -i $INV 2>&1 | tee ~/logs/01-bootstrap.log
bash ~/cloudjudge/infra/kolla/swift-rings.sh
kolla-ansible prechecks -i $INV 2>&1 | tee ~/logs/02-prechecks.log
tmux new -d -s deploy "source ~/kolla-venv/bin/activate && kolla-ansible deploy -i $INV 2>&1 | tee ~/logs/03-deploy.log"
# theo dõi: ssh cj-ctl 'tail -n 30 ~/logs/03-deploy.log'
kolla-ansible post-deploy -i $INV
pip install python-openstackclient python-heatclient python-octaviaclient python-swiftclient
```
Cần `mkdir -p ~/logs` trước khi chạy.

### 7.7. Kiểm tra (✅)
```bash
source /etc/kolla/admin-openrc.sh
openstack service list
openstack compute service list          # nova-compute trên os-compute-1, os-compute-2 đều "up"
openstack network agent list            # OVS agent trên 3 node, L3/DHCP trên controller
openstack volume service list           # cinder-volume@lvm-1 "up"
openstack container create smoke && openstack container list && openstack container delete smoke
openstack orchestration service list
openstack loadbalancer provider list    # có "amphora"
```
Kiểm tra KVM thật: `ssh cj-c1 'sudo docker exec nova_libvirt virsh capabilities | grep -c kvm'` > 0.

---

## 8. Phase 4 – Khởi tạo OpenStack (≈ 1,5 giờ) — A

### 8.1. AZ, flavor, image (`infra/bootstrap/10-az-flavor-image.sh`)
```bash
source /etc/kolla/admin-openrc.sh
openstack aggregate create --zone az1 agg-az1 && openstack aggregate add host agg-az1 os-compute-1
openstack aggregate create --zone az2 agg-az2 && openstack aggregate add host agg-az2 os-compute-2
openstack availability zone list --compute --long

openstack flavor create cj.tiny   --vcpus 1 --ram 512  --disk 10 --public
openstack flavor create cj.small  --vcpus 1 --ram 1024 --disk 10 --public
openstack flavor create cj.medium --vcpus 1 --ram 2048 --disk 20 --public

wget -q https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
openstack image create ubuntu-24.04 --disk-format qcow2 --container-format bare --public --file noble-server-cloudimg-amd64.img
wget -q https://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img
openstack image create cirros --disk-format qcow2 --container-format bare --public --file cirros-0.6.2-x86_64-disk.img
```

### 8.2. Mạng external (`20-extnet.sh`)
```bash
openstack network create --external --share --provider-network-type flat --provider-physical-network physnet1 ext-net
openstack subnet create ext-subnet --network ext-net --subnet-range 172.24.4.0/24 \
  --gateway 172.24.4.1 --no-dhcp --allocation-pool start=172.24.4.10,end=172.24.4.250
```

### 8.3. Ảnh amphora (`60-amphora.sh`)
```bash
wget -q https://tarballs.opendev.org/openstack/octavia/test-images/test-only-amphora-x64-haproxy-ubuntu-noble.qcow2
source /etc/kolla/octavia-openrc.sh
openstack image create amphora-x64-haproxy --container-format bare --disk-format qcow2 --private \
  --tag amphora --property hw_architecture='x86_64' --property hw_rng_model=virtio \
  --file test-only-amphora-x64-haproxy-ubuntu-noble.qcow2
```
Nếu amphora không chuyển sang ACTIVE do lệch phiên bản agent: build image bằng `octavia/diskimage-create/diskimage-create.sh` trên nhánh 2024.2 (xem tài liệu Kolla Octavia).

### 8.4. Smoke test (✅ **MỐC QUYẾT ĐỊNH**, chậm nhất 31/10)
Làm trong project admin, xong thì xóa:
1. Tạo network/subnet test, router có gateway ext-net.
2. Tạo 2 VM cirros, `--availability-zone az1` và `az2`. Cả hai phải **ACTIVE trong < 60 giây**.
3. Vào console, `ping 8.8.8.8` từ VM được (tức là SNAT → veth → MASQUERADE đã chạy).
4. Từ VM: `curl http://10.10.0.10:5000/v3` trả JSON (tenant gọi được API OpenStack).
5. Tạo LB test có 2 member chạy `python3 -m http.server` (dùng image ubuntu). `openstack loadbalancer amphora list` có 2 amphora `MASTER`/`BACKUP` nằm ở 2 compute khác nhau.
6. `ping -M do -s 1422 <ip VM khác>` không bị lỗi MTU.

> **Nếu đến 31/10 bước 1–4 vẫn không chạy được:** dừng lại, báo thầy và chuyển sang AWS theo cách đổi 1–1 đã ghi trong đề xuất (Swift→S3, Cinder→EBS, Octavia→ALB, Heat→ASG). Phần ứng dụng của B và C giữ nguyên.
> **Nếu chỉ riêng Octavia lỗi:** thử `loadbalancer_topology = SINGLE`; vẫn lỗi thì dùng 2 VM HAProxy + keepalived (D3). Không để Octavia chặn cả tiến độ.

### 8.5. Project, user, quota (`30-project-users.sh`)
```bash
openstack project create cloudjudge
openstack role add --project cloudjudge --user admin admin
for u in cj-web cj-worker cj-monitor cj-backup; do
  openstack user create --project cloudjudge --password "$(openssl rand -hex 16 | tee ~/secrets/pw-$u)" $u
done
openstack role add --project cloudjudge --user cj-web member
for u in cj-worker cj-monitor cj-backup; do openstack role add --project cloudjudge --user $u reader; done
openstack quota set --instances 20 --cores 30 --ram 40960 --volumes 10 --gigabytes 100 --secgroups 20 cloudjudge
```
Mỗi thành viên nhóm có 1 user riêng, role `admin` trên `cloudjudge`, dùng khi chạy Heat.

### 8.6. Application credential (`40-appcreds.sh`)
Đăng nhập **bằng chính user đó** rồi tạo; kết quả ghi vào `~/secrets/secrets.env`:
```bash
for u in cj-web cj-worker cj-monitor cj-backup; do
  OUT=$(openstack --os-username $u --os-password "$(cat ~/secrets/pw-$u)" --os-project-name cloudjudge \
        --os-user-domain-name Default --os-project-domain-name Default \
        application credential create ${u}-ac -f json)
  V=$(echo ${u^^} | tr - _)
  echo "${V}_AC_ID=$(echo $OUT | jq -r .id)"     >> ~/secrets/secrets.env
  echo "${V}_AC_SECRET=$(echo $OUT | jq -r .secret)" >> ~/secrets/secrets.env
done
chmod 600 ~/secrets/secrets.env
```

### 8.7. Swift container và ACL (`50-swift-acl.sh`, chạy với scope admin@cloudjudge)
```bash
PID=$(openstack project show cloudjudge -f value -c id)
uid(){ openstack user show $1 -f value -c id; }
W=$(uid cj-worker); B=$(uid cj-backup)
for c in submissions testcases releases backups; do openstack container create $c; done
swift post submissions --read-acl "$PID:$W"
swift post testcases   --read-acl "$PID:$W"
swift post releases    --read-acl "$PID:$W,$PID:$B"
swift post backups     --write-acl "$PID:$B" --read-acl "$PID:$B"
```
✅ Thử bằng app credential của worker: `swift list submissions` được, còn `swift delete submissions x` phải ra **403**.

---

## 9. Phase 5 – Golden image `cj-base-v1` (≈ 1 giờ) — B

Không cần SSH: VM builder tự chạy script qua user-data, xong tự tắt, rồi mình snapshot.

`image/build-cj-base.sh` (user-data):
```bash
#!/bin/bash
set -eux
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y docker.io python3-venv python3-pip prometheus-node-exporter mysql-client jq curl
systemctl enable docker prometheus-node-exporter
python3 -m venv /opt/cj/venv
/opt/cj/venv/bin/pip install flask gunicorn sqlalchemy pymysql pika python-swiftclient keystoneauth1 \
    prometheus-client prometheus-flask-exporter python-openstackclient
docker pull mysql:8.4
docker pull rabbitmq:4.1-management
docker pull prom/prometheus:latest
docker pull prom/alertmanager:latest
docker pull grafana/grafana-oss:latest
docker pull prom/mysqld-exporter:latest
mkdir -p /opt/cj/sandbox && cat > /opt/cj/sandbox/Dockerfile <<'EOF'
FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends g++ && rm -rf /var/lib/apt/lists/*
RUN useradd -u 10001 -m runner
WORKDIR /work
EOF
docker build --network host -t cj-sandbox:1 /opt/cj/sandbox
curl -fsSL https://tailscale.com/install.sh | sh && systemctl disable tailscaled   # chỉ bastion mới bật
# Script tải release từ Swift, dùng khi boot
cat > /opt/cj/fetch-release.sh <<'EOF'
#!/bin/bash
# $1 = version. Credential đọc từ /etc/cloudjudge/cloudjudge.env
set -eu; source /etc/cloudjudge/cloudjudge.env
cd /opt/cj && /opt/cj/venv/bin/swift --os-auth-type v3applicationcredential --os-auth-url "$OS_AUTH_URL" \
  --os-application-credential-id "$OS_AC_ID" --os-application-credential-secret "$OS_AC_SECRET" \
  download releases "cloudjudge-$1.tar.gz" -o app.tar.gz
rm -rf app && mkdir app && tar xzf app.tar.gz -C app
EOF
chmod +x /opt/cj/fetch-release.sh
cloud-init clean --logs --machine-id     # để máy tạo từ image chạy lại cloud-init
poweroff
```
Lệnh build:
```bash
openstack --os-project-name cloudjudge server create cj-builder --image ubuntu-24.04 --flavor cj.medium \
  --network net-public --security-group default --user-data image/build-cj-base.sh --wait
# chờ trạng thái SHUTOFF (~10–15 phút): openstack server show cj-builder -c status
openstack server image create --name cj-base-v1 --wait cj-builder
openstack server delete cj-builder
```
(Cần làm stack `cj-net` ở Phase 7 trước để có `net-public`; hoặc tạm dùng mạng test ở 8.4.)

---

## 10. Phase 6 – Ứng dụng (song song từ ngày 1) — B (web, worker), C (CSDL)

### 10.1. Chạy local (không cần OpenStack)
`app/docker-compose.dev.yml` gồm: `mysql:8.4`, `rabbitmq:4.1-management`, `openstackswift/saio` (Swift dùng tempauth). `common/storage.py` hỗ trợ 2 chế độ: `STORAGE_AUTH=tempauth` (local) và `appcred` (trên cloud).

### 10.2. Lược đồ CSDL (C)
```sql
users(id PK, username UNIQUE, password_hash, role ENUM('student','teacher'), api_token, created_at)
problems(id PK, slug UNIQUE, title, statement_md TEXT, time_limit_ms INT, memory_mb INT,
         testcases_object VARCHAR(255), created_by FK users, created_at)
submissions(id PK, user_id FK, problem_id FK, language ENUM('cpp','python'), source_object VARCHAR(255),
            status ENUM('PENDING','RUNNING','ACCEPTED','WRONG_ANSWER','TIME_LIMIT','RUNTIME_ERROR','COMPILE_ERROR','SYSTEM_ERROR'),
            score INT, passed INT, total INT, runtime_ms INT, worker_host VARCHAR(64),
            created_at, started_at, finished_at, INDEX(status, created_at))
```
User MySQL tối thiểu: `cj_app` (SELECT, INSERT, UPDATE trên `cloudjudge.*`), `cj_ro` (SELECT, dùng ở replica), `repl` (REPLICATION SLAVE), `exporter` (PROCESS, REPLICATION CLIENT, SELECT).

### 10.3. Web/API (B) – Flask + Gunicorn, **không lưu trạng thái**
| Route | Chức năng |
|---|---|
| `GET /login`, `POST /login`, `/logout` | session bằng cookie ký (`SECRET_KEY` dùng chung cho mọi máy web) |
| `GET /problems`, `/problems/<slug>` | danh sách và đề bài |
| `POST /problems/<slug>/submit` | lưu mã lên Swift `submissions/<uuid>`, INSERT `PENDING` vào **Primary**, publish `submission_id` vào queue `submissions` (durable, persistent) |
| `GET /submissions/<id>` | trạng thái, tự refresh 2 giây |
| `GET /scoreboard` | **đọc từ Replica** (minh chứng hạng mục 4) |
| `GET/POST /teacher/problems/new` | giảng viên tạo bài và upload `tests.zip` (`1.in/1.out…`) lên Swift `testcases` |
| `POST /api/submit` | JSON, xác thực bằng header `X-API-Token`, dùng cho script tạo tải |
| `GET /healthz` | trả 200 kèm hostname (Octavia health check; khi demo failover sẽ thấy hostname đổi) |
| `GET /metrics` | `cj_submissions_total`, `cj_pending_submissions`, `cj_oldest_pending_seconds` (truy vấn DB khi được scrape) |

Gunicorn: `-w 3 -b 0.0.0.0:8000`. Footer trang hiển thị **hostname + AZ** (đọc từ metadata `http://169.254.169.254/openstack/latest/meta_data.json`) để demo thấy LB chia tải sang 2 AZ.

### 10.4. Worker (B)
- `pika` với `basic_qos(prefetch_count=1)`, ack thủ công **sau khi** ghi DB (at-least-once; cập nhật idempotent theo `submission_id`, bỏ qua nếu đã có kết quả cuối).
- Quy trình: đặt `RUNNING` → tải mã + `tests.zip` từ Swift → biên dịch (cpp: `g++ -O2 -std=c++17`) → chạy từng test:
  ```
  docker run --rm --network none --read-only --tmpfs /tmp:rw,size=16m \
    --memory 256m --memory-swap 256m --cpus 1 --pids-limit 64 --cap-drop ALL \
    --security-opt no-new-privileges --user 10001:10001 -v <workdir>:/work:ro \
    cj-sandbox:1 timeout <TL>s <cmd>
  ```
  → so sánh output (bỏ khoảng trắng cuối) → UPDATE kết quả → ack.
- Lỗi hệ thống: đánh dấu `SYSTEM_ERROR` rồi ack, tránh vòng lặp vô hạn với bài độc.
- Log có hostname, để demo thấy bài được chia cho nhiều máy chấm.

### 10.5. Đóng gói release
`scripts/release.sh <ver>`: tạo `cloudjudge-<ver>.tar.gz` gồm `app/` và `deploy/` (`install.sh <role>`, `systemd/cj-web.service`, `systemd/cj-worker.service`), rồi `swift upload releases`. Heat truyền `release_version`. Đổi code = upload bản mới + `openstack stack update` với version mới (ASG sẽ thay máy).

### 10.6. Dữ liệu demo
- `slow-sum`: 4 test, lời giải mẫu chạy ~1,5 giây/test → ~7–8 giây/bài → **~8 bài/phút/worker** (khớp giả định "7 bài/phút" trong đề xuất).
- `a-plus-b`: bài nhanh, dùng cho phần "nộp 1 đúng, 1 sai".
- 1 tài khoản giảng viên, 5 tài khoản sinh viên, 1 tài khoản `loadtest` có API token.

---

## 11. Phase 7 – Heat stacks (≈ 1,5 ngày) — A: cj-net · C: cj-data, cj-mon · B: cj-app

Thứ tự: **cj-net → cj-data → cj-app → cj-mon**. Mỗi stack nhận ID từ output của stack trước, qua `scripts/deploy-stacks.sh`. Secret lấy từ `~/secrets/secrets.env` và truyền bằng `--parameter` (tham số `hidden: true`).

### 11.1. `cj-net.yaml` (A)
- `OS::Neutron::Net` + `Subnet` ×3 (theo 3.2, `dns_nameservers: [8.8.8.8]`, có `allocation_pools`).
- `OS::Neutron::Router` (`external_gateway_info: {network: ext-net}`) + `RouterInterface` ×3.
- 6 `OS::Neutron::SecurityGroup` theo 3.3 (dùng `remote_mode: remote_group_id`).
- Bastion: `OS::Nova::Server` (cj.tiny, net-public, `availability_zone: az1`) + `OS::Neutron::FloatingIP`. Cloud-init chạy `systemctl enable --now tailscaled; tailscale up --authkey=$TS_BASTION_KEY --hostname=cj-bastion --advertise-routes=10.0.2.0/24,10.0.3.0/24` và bật `ip_forward`.
- Output: id các network/subnet/SG, IP bastion.

### 11.2. `cj-data.yaml` (C)
- Tạo `OS::Cinder::Volume`: mysql-primary 10 GB (az1), mysql-replica 10 GB (az2), rabbitmq 5 GB.
- Server gắn volume bằng `block_device_mapping_v2: [{boot_index: -1, volume_id: ..., delete_on_termination: false}]`; port có `fixed_ips` cố định theo 3.2.
- Cloud-init cho mỗi vai trò: `blkid /dev/vdb || mkfs.ext4 -L cjdata /dev/vdb` → mount `/data` (ghi vào fstab) → `docker run --restart unless-stopped --network host -v /data/...`.
  - **Primary**: `mysql:8.4 --server-id=1 --gtid-mode=ON --enforce-gtid-consistency=ON --log-bin=mysql-bin --binlog-format=ROW`; tạo DB, user (10.2), user `repl`; chạy schema.
  - **Replica**: `--server-id=2 --read-only=ON --super-read-only=ON`, chờ Primary sẵn sàng rồi
    `CHANGE REPLICATION SOURCE TO SOURCE_HOST='10.0.3.10', SOURCE_USER='repl', SOURCE_PASSWORD='…', SOURCE_AUTO_POSITION=1, GET_SOURCE_PUBLIC_KEY=1; START REPLICA;`
  - **RabbitMQ**: `rabbitmq:4.1-management`; `enabled_plugins` = `[rabbitmq_management,rabbitmq_prometheus].`; `rabbitmq.conf` có `prometheus.return_per_object_metrics = true`; user `cj`.
  - `mysqld-exporter` (cổng 9104) trên cả 2 máy MySQL.
  - **Backup** (trên primary, dùng credential `cj-backup`): cron 02:00 chạy `scripts/backup-mysql.sh` = `mysqldump --single-transaction` | gzip | `swift upload backups --object-name mysql-<time>.sql.gz` với header `X-Delete-After: 604800`.
- Output: IP DB/MQ.

### 11.3. `cj-app.yaml` (B)
```yaml
heat_template_version: 2021-04-16
# parameters: image, flavors, net/subnet ids, sg ids, ext_net, release_version,
#             secrets (hidden: true): db_pass, mq_pass, secret_key, web/worker appcred id/secret
resources:
  web_group:    {type: OS::Nova::ServerGroup, properties: {name: cj-web-group,    policies: [soft-anti-affinity]}}
  worker_group: {type: OS::Nova::ServerGroup, properties: {name: cj-worker-group, policies: [soft-anti-affinity]}}
  lb:
    type: OS::Octavia::LoadBalancer
    properties: {vip_subnet: {get_param: public_subnet}}
  listener:
    type: OS::Octavia::Listener
    properties: {loadbalancer: {get_resource: lb}, protocol: HTTP, protocol_port: 80}
  pool:
    type: OS::Octavia::Pool
    properties: {listener: {get_resource: listener}, lb_algorithm: ROUND_ROBIN, protocol: HTTP}
  monitor:
    type: OS::Octavia::HealthMonitor
    properties: {pool: {get_resource: pool}, type: HTTP, url_path: /healthz, delay: 5, timeout: 3, max_retries: 2}
  lb_fip:
    type: OS::Neutron::FloatingIP
    properties: {floating_network: {get_param: ext_net}, port_id: {get_attr: [lb, vip_port_id]}}
  web_asg:
    type: OS::Heat::AutoScalingGroup
    properties:
      min_size: 2
      max_size: 3
      desired_capacity: 2
      resource:
        type: CJ::WebMember
        properties: {pool_id: {get_resource: pool}, server_group: {get_resource: web_group}, ...}
  worker_asg:
    type: OS::Heat::AutoScalingGroup
    properties:
      min_size: 1
      max_size: 3
      desired_capacity: 1
      resource: {type: CJ::Worker, properties: {server_group: {get_resource: worker_group}, ...}}
  web_up:      {type: OS::Heat::ScalingPolicy, properties: {adjustment_type: change_in_capacity, auto_scaling_group_id: {get_resource: web_asg},    scaling_adjustment: 1,  cooldown: 120}}
  web_down:    {type: OS::Heat::ScalingPolicy, properties: {adjustment_type: change_in_capacity, auto_scaling_group_id: {get_resource: web_asg},    scaling_adjustment: -1, cooldown: 300}}
  worker_up:   {type: OS::Heat::ScalingPolicy, properties: {adjustment_type: change_in_capacity, auto_scaling_group_id: {get_resource: worker_asg}, scaling_adjustment: 1,  cooldown: 60}}
  worker_down: {type: OS::Heat::ScalingPolicy, properties: {adjustment_type: change_in_capacity, auto_scaling_group_id: {get_resource: worker_asg}, scaling_adjustment: -1, cooldown: 60}}
outputs:
  lb_fip:          {value: {get_attr: [lb_fip, floating_ip_address]}}
  web_up_url:      {value: {get_attr: [web_up, alarm_url]}}
  web_down_url:    {value: {get_attr: [web_down, alarm_url]}}
  worker_up_url:   {value: {get_attr: [worker_up, alarm_url]}}
  worker_down_url: {value: {get_attr: [worker_down, alarm_url]}}
```
`heat/env/cj-app.env.yaml`:
```yaml
resource_registry:
  "CJ::WebMember": ../web_member.yaml
  "CJ::Worker": ../worker.yaml
```
`web_member.yaml` (template con):
```yaml
heat_template_version: 2021-04-16
parameters: {image: {type: string}, flavor: {type: string}, network: {type: string}, security_group: {type: string},
             server_group: {type: string}, pool_id: {type: string}, user_data: {type: string}}
resources:
  port:
    type: OS::Neutron::Port
    properties: {network: {get_param: network}, security_groups: [{get_param: security_group}]}
  server:
    type: OS::Nova::Server
    properties:
      image: {get_param: image}
      flavor: {get_param: flavor}
      networks: [{port: {get_resource: port}}]
      scheduler_hints: {group: {get_param: server_group}}
      metadata: {cj_role: web}
      user_data_format: RAW
      user_data: {get_param: user_data}
  member:
    type: OS::Octavia::PoolMember
    properties:
      pool: {get_param: pool_id}
      address: {get_attr: [port, fixed_ips, 0, ip_address]}
      protocol_port: 8000        # KHÔNG khai báo subnet (xem ghi chú 3.3)
```
`worker.yaml` tương tự nhưng không có member, `metadata: {cj_role: worker}`. User-data của web/worker: ghi `/etc/cloudjudge/cloudjudge.env` (chmod 600) → `/opt/cj/fetch-release.sh $VER` → `/opt/cj/app/deploy/install.sh web|worker`.

Sau khi tạo stack: ghi IP floating của LB vào `/etc/cloudjudge/lb_fip` trên controller, chạy lại `cj-nat.sh`. ✅ Mở `http://<CTL_IP>` từ trình duyệt laptop, nộp 1 bài và nhận được điểm.

### 11.4. `cj-mon.yaml` (C)
- 1 server cj.medium, net-app, IP 10.0.2.11, `metadata: {cj_role: monitor}`. Cloud-init sinh file cấu hình từ template rồi `docker compose up -d` (Prometheus, Alertmanager, Grafana).
- Tham số: credential `cj-monitor` (hidden), Gmail user + **App Password** (hidden), 4 `alarm_url` lấy từ output `cj-app` (hidden, vì là URL đã ký).

---

## 12. Phase 8 – Giám sát và tự mở rộng (≈ 1,5 ngày) — C (giám sát), B (co giãn)

### 12.1. `prometheus.yml` (rút gọn)
```yaml
global: {scrape_interval: 5s, evaluation_interval: 5s}
rule_files: [/etc/prometheus/rules.yml]
alerting: {alertmanagers: [{static_configs: [{targets: ['localhost:9093']}]}]}
scrape_configs:
  - job_name: node
    openstack_sd_configs:
      - role: instance
        region: RegionOne
        identity_endpoint: http://10.10.0.10:5000/v3
        application_credential_id: "${MON_AC_ID}"
        application_credential_secret: "${MON_AC_SECRET}"
        port: 9100
    relabel_configs:
      - {source_labels: [__meta_openstack_instance_status], regex: ACTIVE, action: keep}
      - {source_labels: [__meta_openstack_tag_cj_role], target_label: role}
      - {source_labels: [__meta_openstack_instance_name], target_label: instance}
  - job_name: web
    openstack_sd_configs: [ ...như trên, port: 8000 ]
    relabel_configs:
      - {source_labels: [__meta_openstack_tag_cj_role], regex: web, action: keep}
      - {source_labels: [__meta_openstack_instance_name], target_label: instance}
  - job_name: rabbitmq
    static_configs: [{targets: ['10.0.2.10:15692']}]
  - job_name: mysql
    static_configs: [{targets: ['10.0.3.10:9104', '10.0.3.11:9104']}]
```
(`${…}` do cloud-init thay bằng `envsubst`; bản thân Prometheus không tự đọc biến môi trường.)

### 12.2. `rules.yml`
```yaml
groups:
- name: cloudjudge
  rules:
  - alert: QueueHigh
    expr: sum(rabbitmq_queue_messages_ready{queue="submissions"}) > 10
    for: 30s
    labels: {severity: warning, action: worker_up}
    annotations: {summary: "Hàng đợi chấm dài: {{ $value }} bài"}
  - alert: QueueIdle
    expr: sum(rabbitmq_queue_messages{queue="submissions"}) == 0 and count(up{job="node",role="worker"} == 1) > 1
    for: 1m
    labels: {action: worker_down}
  - alert: WebCPUHigh
    expr: avg(1 - rate(node_cpu_seconds_total{mode="idle",role="web"}[1m])) > 0.7
    for: 1m
    labels: {severity: warning, action: web_up}
  - alert: WebCPULow
    expr: avg(1 - rate(node_cpu_seconds_total{mode="idle",role="web"}[1m])) < 0.2 and count(up{job="web"} == 1) > 2
    for: 5m
    labels: {action: web_down}
  - alert: SubmissionStuck
    expr: max(cj_oldest_pending_seconds) > 120
    labels: {severity: critical}
    annotations: {summary: "Có bài chờ chấm quá 2 phút"}
  - alert: InstanceDown
    expr: up == 0
    for: 1m
    labels: {severity: critical}
```

### 12.3. `alertmanager.yml`
```yaml
global:
  smtp_smarthost: 'smtp.gmail.com:587'      # GCE chặn cổng 25
  smtp_from: '${SMTP_USER}'
  smtp_auth_username: '${SMTP_USER}'
  smtp_auth_password: '${SMTP_APP_PASSWORD}'
  smtp_require_tls: true
route:
  receiver: email
  group_by: [alertname]
  group_wait: 10s
  group_interval: 30s
  repeat_interval: 1h
  routes:
    - {matchers: ['action="worker_up"'],   receiver: worker-up,   repeat_interval: 1m, continue: true}
    - {matchers: ['action="worker_down"'], receiver: worker-down, repeat_interval: 1m}
    - {matchers: ['action="web_up"'],      receiver: web-up,      repeat_interval: 2m, continue: true}
    - {matchers: ['action="web_down"'],    receiver: web-down,    repeat_interval: 5m}
    - {matchers: ['severity=~"warning|critical"'], receiver: email}
receivers:
  - name: email
    email_configs: [{to: '${ALERT_EMAIL_TO}', send_resolved: true}]
  - {name: worker-up,   webhook_configs: [{url: '${WORKER_UP_URL}',   send_resolved: false}]}
  - {name: worker-down, webhook_configs: [{url: '${WORKER_DOWN_URL}', send_resolved: false}]}
  - {name: web-up,      webhook_configs: [{url: '${WEB_UP_URL}',      send_resolved: false}]}
  - {name: web-down,    webhook_configs: [{url: '${WEB_DOWN_URL}',    send_resolved: false}]}
```
Kiểm tra trước khi nối Alertmanager: từ máy monitor chạy `curl -X POST "$WORKER_UP_URL"` → `openstack stack resource list -n 2 cj-app` phải thấy thêm 1 worker. Nếu không chạy, dùng adapter (D11).

### 12.4. Grafana
Datasource Prometheus và 1 dashboard (provisioning bằng file trong `monitoring/grafana/`): hàng đợi, số worker `count(up{role="worker"})`, bài chấm/phút `rate(cj_submissions_total[1m])`, `cj_oldest_pending_seconds`, CPU theo vai trò, trạng thái replica MySQL.

### 12.5. `scripts/loadtest.py`
`python loadtest.py --base http://<CTL_IP> --token <api_token> --problem slow-sum --n 60 --concurrency 10`. In ra số bài đã gửi, sau đó theo dõi đến khi toàn bộ có kết quả cuối; tính thời gian chờ trung bình và p95 (dùng cho báo cáo).

### 12.6. Điều chỉnh thời gian (✅ đo và ghi vào mục 17)
Đo: thời gian từ khi alert firing đến khi worker mới ACTIVE và nhận bài; thời gian thu về 1 worker. Mục tiêu khớp kịch bản demo: worker thứ 2 xuất hiện **trước phút 4:00**, thu về 1 **trước phút 9:00**. Nếu chậm thì giảm `for:`, giảm cooldown, hoặc giảm số bài.

---

## 13. Phase 9 – Kiểm thử bảo mật, failover, minh chứng — A (bảo mật, mạng), B (failover), C (DB, giám sát)

`scripts/demo-checks.sh` chạy các lệnh dưới đây và lưu output vào `docs/evidence/`. Chụp ảnh màn hình ngay khi làm.

| HM | Kiểm tra | Kết quả mong đợi |
|---|---|---|
| 1 | Horizon → Network Topology; `openstack server list --long -c Name -c Status -c Networks -c "Availability Zone"` | 3 network, 1 router; web/worker nằm ở cả az1 và az2 |
| 2 | `openstack floating ip list` | chỉ có VIP của LB và bastion |
| 2 | từ worker: `curl -m 5 http://<web-ip>:8000/healthz` | timeout (bị chặn) |
| 2 | từ laptop: `curl http://<CTL_IP>/healthz` | 200 + hostname |
| 3 | `openstack container list`; `openstack object list submissions`; `openstack volume list --long` | có object mới; volume "in-use" gắn vào mysql/rabbit |
| 4 | INSERT ở Primary → SELECT ở Replica; `SHOW REPLICA STATUS\G` | dữ liệu đã đồng bộ; `Replica_IO_Running: Yes` |
| 5 | `openstack application credential list` (từng user); từ worker `swift delete submissions <obj>` | 403 Forbidden |
| 5 | `git grep -nIE "(secret|password|AC_SECRET)\s*[:=]\s*\S{8,}"`; `gitleaks detect` | không có kết quả / "no leaks found" |
| 6 | `openstack loadbalancer amphora list` | 2 amphora MASTER/BACKUP ở 2 host |
| 6 | chạy loadtest → `openstack stack resource list -n 2 cj-app` | số worker 1 → 2 → 3 → 1 |
| 6 | tắt 1 web ở az1 (`openstack server stop`) → refresh trang | vẫn chạy, hostname là máy ở az2 |
| 7 | Grafana + hộp thư | email `QueueHigh` / `SubmissionStuck` tới |
| 8 | `docs/cost.xlsx` + ảnh Billing GCP | 3 phương án như đề xuất + chi phí thật |

Thử thêm failover amphora: `openstack server stop <amphora MASTER>` (bằng admin) → LB vẫn trả lời. Làm 1 lần để có ảnh; **không** đưa vào demo chính.

---

## 14. Phase 10 – Demo, video, báo cáo, bảo vệ

### 14.1. Kịch bản demo 10 phút (giữ như đề xuất; A/B/C = người phụ trách)
| Thời gian | Người | Thao tác | Kết quả mong đợi |
|---|---|---|---|
| 0:00–1:00 | A | Network Topology, AZ, danh sách máy | 3 network, 1 router, máy ở cả 2 AZ |
| 1:00–1:20 | B | Chạy nền `loadtest.py --n 60` | Hàng đợi tăng (Grafana) |
| 1:20–2:45 | B, C | Nộp 1 bài đúng, 1 bài sai; xem Swift và Cinder | 100 điểm / báo lỗi; có object mới; volume đã gắn |
| 2:45–4:00 | A | Floating IP, security group, xóa object, `git grep` | Bị chặn đúng chỗ; 403; không có khóa |
| 4:00–6:00 | B, C | Grafana, hộp thư, tài nguyên Heat | Email cảnh báo; Heat đã thêm máy chấm |
| 6:00–7:00 | B | Tắt 1 Web/API ở AZ-1 | Web vẫn chạy qua máy ở AZ-2 |
| 7:00–7:45 | C | Ghi ở Primary, đọc ở Replica | Dữ liệu đã đồng bộ |
| 7:45–9:00 | B, C | Số bài đã chấm, Grafana | Chấm đủ 60 bài; máy chấm thu về 1 |
| 9:00–10:00 | C | Bảng chi phí, hóa đơn GCP | |

### 14.2. Trước mỗi buổi demo hoặc quay video
1. `infra/gcp/gcp-up.sh` **trước ít nhất 1,5–2 giờ** (máy ảo lồng và amphora khởi động chậm).
2. `ssh cj-ctl 'bash ~/cloudjudge/scripts/cj-health.sh'`: kiểm tra container Kolla, `openstack server list` toàn ACTIVE, LB `ONLINE`, replica chạy, worker = 1, web = 2, hàng đợi rỗng.
3. Mở sẵn các tab: Horizon, Grafana (qua Tailscale), Gmail, terminal.
4. Bật web lại nếu buổi trước đã tắt để demo (`openstack server start`), hoặc chạy `openstack stack check cj-app`.

### 14.3. Video (8/11)
Quay bằng OBS đúng kịch bản 14.1, dài ≤ 12 phút, có giọng thuyết minh. Upload Google Drive / YouTube (unlisted), dán link vào báo cáo.

### 14.4. Báo cáo cuối (C ghép; mỗi người viết phần mình)
1. Bài toán. 2. Kiến trúc (sơ đồ cập nhật đúng thực tế). 3. **Dựng OpenStack trên GCP**: nested virt, mạng external giả, MTU, Kolla 2024.2 (vì sao). 4. Bảng đối chiếu 8 hạng mục kèm ảnh minh chứng (mục 13). 5. Lý giải lựa chọn công nghệ, có các điểm **≠ đề xuất** ở mục 2. 6. Kết quả đo: thời gian chấm lúc thường và cao điểm, thời gian scale out/in. 7. Chi phí (thật + 3 phương án). 8. Giới hạn: controller là điểm lỗi đơn, CPU vật lý cố định, secret chưa dùng Barbican/Vault, amphora là image test. 9. Phân công thực tế, link repo, link video.

### 14.5. Chuẩn bị vấn đáp (hỏi chéo nhau từ 10/11)
- **A:** VXLAN overlay; router SNAT và floating IP (DNAT); veth/br-ex; security group (có trạng thái) khác NACL thế nào; application credential so với IAM role / instance profile; least privilege; vì sao AZ ở đây tương đương host; nested virtualization.
- **B:** LB L4 và L7; health check; active/standby bằng VRRP; vì sao web phải stateless; co giãn theo hàng đợi chứ không theo CPU; cooldown và flapping; at-least-once delivery; sandbox (namespace, cgroup, `--network none`).
- **C:** object, block, file storage; replication đồng bộ và bất đồng bộ, GTID, RPO/RTO; vì sao không dùng Trove; Prometheus pull model và service discovery; cách tính chi phí, TCO.
- **Chung (CLO2):** IaaS/PaaS/SaaS; các loại ảo hóa; elasticity khác scalability thế nào; mô hình trách nhiệm chia sẻ; vì sao một web app trên 1 VM không phải là "dùng đám mây".

---

## 15. Vận hành hằng ngày và xử lý sự cố

### 15.1. Bật/tắt
- Bắt đầu buổi: `gcp-up.sh` → chờ ~5 phút → `cj-health.sh`. Kolla container tự khởi động lại (`restart: unless-stopped`); VM OpenStack tự bật lại nhờ `resume_guests_state_on_host_boot`.
- Kết thúc buổi: `gcp-down.sh`. **Không** cần tắt từng VM OpenStack.
- MariaDB của Kolla không lên sau reboot: `kolla-ansible mariadb_recovery -i $INV`.

### 15.2. Snapshot sau mỗi mốc (tắt máy trước khi chụp)
```bash
gcloud compute disks snapshot os-controller os-controller-cinder os-controller-swift --zone="$ZONE_A" --snapshot-names=ctl-boot-m1,ctl-cinder-m1,ctl-swift-m1
gcloud compute disks snapshot os-compute-1 --zone="$ZONE_A" --snapshot-names=c1-m1
gcloud compute disks snapshot os-compute-2 --zone="$ZONE_B" --snapshot-names=c2-m1
```
Chỉ giữ 2 bộ snapshot gần nhất (`gcloud compute snapshots delete ...` các bộ cũ, **hỏi trước khi xóa**).

### 15.3. Sự cố thường gặp
| Triệu chứng | Kiểm tra / xử lý |
|---|---|
| Không có `/dev/kvm` | VM tạo thiếu `--enable-nested-virtualization` → tạo lại |
| `install-deps` lỗi nhánh | Xem ghi chú ở 7.1 |
| `prechecks` báo cổng 80 bận | Có tiến trình khác nghe cổng 80 trên controller; DNAT không ảnh hưởng prechecks |
| VM ERROR "No valid host" | `openstack resource provider usage show`; tên AZ; `cpu_allocation_ratio`; RAM còn trống |
| VM không ra được Internet | `ip_forward`; luật MASQUERADE; `veth-ex` UP; `docker exec openvswitch_vswitchd ovs-vsctl show` (veth-ex có trong br-ex không); router có gateway chưa |
| Treo khi tải file lớn / TLS | MTU: `ping -M do -s 1422`; kiểm tra `ip link` trong VM là 1450 |
| LB kẹt `PENDING_CREATE` | `/var/log/kolla/octavia/octavia-worker.log`; amphora boot chậm (tăng `amp_active_retries`); interface `o-hm0` trên controller có IP chưa |
| Member `ERROR` / `OFFLINE` | sg-web phải mở 8000 cho 10.0.1.0/24; `/healthz` trả 200 |
| `alarm_url` không scale | `curl -X POST "<url>" -v`; xem log `heat_api_cfn` và `heat_engine` |
| Swift 401/403 sai chỗ | App credential đã đúng project chưa; ACL dạng `<project_id>:<user_id>` |
| Không nhận email | App Password Gmail; cổng 587; xem thư mục spam; log container alertmanager |
| Credit tụt nhanh | `gcloud billing ...` / trang Billing; có quên tắt máy không |

---

## 16. Lịch và phân công

| Ký hiệu | Mảng | Thành viên (điền) |
|---|---|---|
| A | Hạ tầng GCP + OpenStack, mạng, phân quyền (HM 1, 2, 5) | |
| B | Ứng dụng, image, LB, tự mở rộng (HM 6) | |
| C | Lưu trữ, CSDL, giám sát, chi phí, ghép báo cáo (HM 3, 4, 7, 8) | |

| Ngày | A | B | C | Mốc |
|---|---|---|---|---|
| T4 28/10 | Phase 0, Phase 1 | Khung repo, compose dev | Schema, script replication local | VM GCP có `/dev/kvm` |
| T5 29/10 | Phase 2, Phase 3 (deploy) | Web: login, nộp bài, Swift | Rules và Alertmanager email (local) | |
| T6 30/10 | Phase 4 (8.1–8.4) | Worker + sandbox (local) | Bảng chi phí nháp | |
| T7 31/10 | 8.5–8.7, `cj-net` | Phase 5 image, `release.sh` | `cj-data` | **Mốc quyết định smoke test** |
| CN 1/11 | Tailscale bastion, kiểm SG | `cj-app` (LB + ASG) | `cj-data` replication, backup | |
| T2 2/11 | Hỗ trợ debug LB/mạng | `cj-app` end-to-end | `cj-mon` | |
| T3 3/11 | Kiểm thử bảo mật | Sửa lỗi app | Grafana dashboard | **Nộp bài qua IP public ra điểm** |
| T4 4/11 | Minh chứng HM 1, 2, 5 | Scaling policy + loadtest | Alert email thật | |
| T5 5/11 | Failover amphora / web | Điều chỉnh thời gian (12.6) | Backup + restore thử | |
| T6 6/11 | — tập demo lần 1 (cả nhóm) — | | | **Demo trọn vẹn** |
| T7 7/11 | Viết báo cáo phần A | Viết báo cáo phần B | Ghép báo cáo, chi phí thật | |
| CN 8/11 | — tập lần 2 + **quay video** — | | | Snapshot bộ "final" |
| T2 9/11 | Dọn repo, README | Kiểm tra lần cuối | Xuất PDF | **NỘP** |
| 10–15/11 | Ôn vấn đáp, tập demo 2 lần (bật cụm ~4 buổi × 3 giờ) | | | |
| T2 16/11 | Bật cụm trước 2 giờ, `cj-health.sh` | | | **BẢO VỆ** |

---

## 17. Trạng thái (cập nhật sau mỗi phiên)

**Giá trị thật:**
- PROJECT_ID: `…`
- BILLING_ID: `…`
- CTL_IP (static): `…`
- LB floating IP: `…`
- Phiên bản Kolla-Ansible thực tế: `…`
- Ghi chú lệch kế hoạch: …

**Tiến độ:**
- [ ] Phase 0 – Laptop, repo, SSH key, Tailscale
- [ ] Phase 1 – GCP: project, budget, VPC, firewall, 3 VM, `/dev/kvm` OK
- [ ] Phase 2 – Host: veth, NAT, LVM, đĩa Swift, Tailscale controller, SSH key Kolla
- [ ] Phase 3 – Kolla deploy + post-deploy, các service đều up
- [ ] Phase 4 – AZ, flavor, image, ext-net, amphora, **smoke test qua**, project/user/app cred, Swift ACL
- [ ] Phase 5 – Image `cj-base-v1`
- [ ] Phase 6 – App chạy local; release v1 đã upload lên Swift
- [ ] Phase 7 – Stack cj-net / cj-data / cj-app / cj-mon; nộp bài qua IP public ra điểm
- [ ] Phase 8 – Cảnh báo email; scale worker 1→3→1; đã đo thời gian
- [ ] Phase 9 – Đủ minh chứng 8 hạng mục trong `docs/evidence/`
- [ ] Phase 10 – Tập demo lần 1 / lần 2; video; báo cáo; nộp 9/11
- [ ] Tổng giờ chạy cụm đến nay: `…` giờ (giới hạn ≤ 300)

**Nhật ký:**
- 28/10/2026: lập kế hoạch.

---

## 18. Tài liệu tham khảo
- Kolla-Ansible 2024.2 – Quickstart: https://docs.openstack.org/kolla-ansible/2024.2/user/quickstart.html
- Kolla-Ansible 2024.2 – Octavia (mục *Development or Testing*, `octavia_network_type: tenant`): https://docs.openstack.org/kolla-ansible/2024.2/reference/networking/octavia.html
- Kolla-Ansible 2024.2 – Swift guide: https://docs.openstack.org/kolla-ansible/2024.2/reference/storage/swift-guide.html
- Release notes Kolla-Ansible 2025.1 (đã bỏ Swift): https://docs.openstack.org/releasenotes/kolla-ansible/2025.1.html
- Release notes 2024.2 (hỗ trợ Ubuntu Noble): https://docs.openstack.org/releasenotes/kolla-ansible/2024.2.html
- Ảnh amphora dựng sẵn (bản test): https://tarballs.opendev.org/openstack/octavia/test-images/
- Heat AutoScalingGroup / ScalingPolicy: https://docs.openstack.org/heat/latest/template_guide/openstack.html
- Prometheus `openstack_sd_config`: https://prometheus.io/docs/prometheus/latest/configuration/configuration/#openstack_sd_config
- GCE nested virtualization: https://cloud.google.com/compute/docs/instances/nested-virtualization/overview
