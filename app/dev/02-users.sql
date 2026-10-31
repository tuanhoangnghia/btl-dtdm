-- User MySQL cho dev local, cùng quyền như trên cụm (CONTRACT mục 8.3). Trên cụm C tạo user này.
CREATE USER IF NOT EXISTS 'cj_app'@'%' IDENTIFIED BY 'dev-app';
GRANT SELECT, INSERT, UPDATE ON cloudjudge.* TO 'cj_app'@'%';
CREATE USER IF NOT EXISTS 'cj_ro'@'%' IDENTIFIED BY 'dev-ro';
GRANT SELECT ON cloudjudge.* TO 'cj_ro'@'%';
FLUSH PRIVILEGES;
