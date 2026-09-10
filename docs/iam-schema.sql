-- ============================================
-- IAM 微服务数据库 Schema
-- ============================================

-- 1. user 服务数据库
CREATE DATABASE IF NOT EXISTS `iam_user_db` DEFAULT CHARSET=utf8mb4;
USE `iam_user_db`;

CREATE TABLE IF NOT EXISTS `iam_user` (
  `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `username` VARCHAR(64) NOT NULL UNIQUE,
  `phone` VARCHAR(20) DEFAULT NULL,
  `email` VARCHAR(128) DEFAULT NULL,
  `nickname` VARCHAR(64) DEFAULT NULL,
  `avatar` VARCHAR(512) DEFAULT NULL,
  `status` VARCHAR(16) NOT NULL DEFAULT 'enabled' COMMENT 'enabled/disabled',
  `department_id` BIGINT DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_username` (`username`),
  INDEX `idx_phone` (`phone`),
  INDEX `idx_email` (`email`),
  INDEX `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `iam_user_tag` (
  `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `user_id` BIGINT NOT NULL,
  `tag_key` VARCHAR(64) NOT NULL,
  `tag_value` VARCHAR(256) DEFAULT NULL,
  UNIQUE KEY `uk_user_tag` (`user_id`, `tag_key`),
  INDEX `idx_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. login 服务数据库
CREATE DATABASE IF NOT EXISTS `iam_login_db` DEFAULT CHARSET=utf8mb4;
USE `iam_login_db`;

CREATE TABLE IF NOT EXISTS `login_session` (
  `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `user_id` BIGINT NOT NULL,
  `token` VARCHAR(512) NOT NULL,
  `refresh_token` VARCHAR(512) NOT NULL,
  `ip` VARCHAR(64) DEFAULT NULL,
  `user_agent` VARCHAR(512) DEFAULT NULL,
  `expires_at` DATETIME NOT NULL,
  `revoked` TINYINT NOT NULL DEFAULT 0,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_user_id` (`user_id`),
  INDEX `idx_token` (`token`(128)),
  INDEX `idx_refresh_token` (`refresh_token`(128))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `login_audit_log` (
  `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `user_id` BIGINT DEFAULT NULL,
  `username` VARCHAR(64) DEFAULT NULL,
  `action` VARCHAR(32) NOT NULL COMMENT 'login/logout/refresh',
  `ip` VARCHAR(64) DEFAULT NULL,
  `user_agent` VARCHAR(512) DEFAULT NULL,
  `result` VARCHAR(16) NOT NULL COMMENT 'success/fail',
  `fail_reason` VARCHAR(256) DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_user_id` (`user_id`),
  INDEX `idx_action` (`action`),
  INDEX `idx_result` (`result`),
  INDEX `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. security 服务数据库
CREATE DATABASE IF NOT EXISTS `iam_security_db` DEFAULT CHARSET=utf8mb4;
USE `iam_security_db`;

CREATE TABLE IF NOT EXISTS `sec_password` (
  `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `user_id` BIGINT NOT NULL UNIQUE,
  `password_hash` VARCHAR(256) NOT NULL,
  `salt` VARCHAR(128) DEFAULT NULL,
  `algo` VARCHAR(16) NOT NULL DEFAULT 'bcrypt',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `sec_mfa` (
  `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `user_id` BIGINT NOT NULL UNIQUE,
  `mfa_type` VARCHAR(16) NOT NULL COMMENT 'totp/sms/email',
  `secret` VARCHAR(256) NOT NULL,
  `backup_codes` TEXT DEFAULT NULL,
  `enabled` TINYINT NOT NULL DEFAULT 0,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `sec_bruteforce` (
  `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `ip` VARCHAR(64) NOT NULL,
  `user_id` BIGINT DEFAULT NULL,
  `fail_count` INT NOT NULL DEFAULT 0,
  `locked_until` DATETIME DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uk_ip_user` (`ip`, `user_id`),
  INDEX `idx_ip` (`ip`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `sec_blacklist` (
  `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `target_type` VARCHAR(16) NOT NULL COMMENT 'ip/email/phone/user_id',
  `target_value` VARCHAR(256) NOT NULL,
  `reason` VARCHAR(512) DEFAULT NULL,
  `expires_at` DATETIME DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_target` (`target_type`, `target_value`(128))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `sec_password_policy` (
  `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `min_length` INT NOT NULL DEFAULT 8,
  `require_upper` TINYINT NOT NULL DEFAULT 1,
  `require_lower` TINYINT NOT NULL DEFAULT 1,
  `require_digit` TINYINT NOT NULL DEFAULT 1,
  `require_special` TINYINT NOT NULL DEFAULT 0,
  `max_age_days` INT NOT NULL DEFAULT 90,
  `history_count` INT NOT NULL DEFAULT 5,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 插入默认密码策略
INSERT INTO `sec_password_policy` (`min_length`) VALUES (8);

-- 4. manage 服务数据库
CREATE DATABASE IF NOT EXISTS `iam_manage_db` DEFAULT CHARSET=utf8mb4;
USE `iam_manage_db`;

CREATE TABLE IF NOT EXISTS `iam_role` (
  `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `name` VARCHAR(64) NOT NULL UNIQUE,
  `arn` VARCHAR(256) NOT NULL UNIQUE,
  `description` VARCHAR(512) DEFAULT NULL,
  `is_system` TINYINT NOT NULL DEFAULT 0,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `iam_policy` (
  `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `name` VARCHAR(128) NOT NULL UNIQUE,
  `arn` VARCHAR(256) NOT NULL UNIQUE,
  `policy_doc` JSON NOT NULL,
  `policy_type` VARCHAR(16) NOT NULL DEFAULT 'managed' COMMENT 'managed/inline',
  `description` VARCHAR(512) DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `iam_user_role` (
  `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `user_id` BIGINT NOT NULL,
  `role_id` BIGINT NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uk_user_role` (`user_id`, `role_id`),
  INDEX `idx_user_id` (`user_id`),
  INDEX `idx_role_id` (`role_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `iam_role_policy` (
  `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `role_id` BIGINT NOT NULL,
  `policy_id` BIGINT NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uk_role_policy` (`role_id`, `policy_id`),
  INDEX `idx_role_id` (`role_id`),
  INDEX `idx_policy_id` (`policy_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 插入默认角色
INSERT INTO `iam_role` (`name`, `arn`, `description`, `is_system`) VALUES
  ('admin', 'arn:iam:123456789:role/admin', 'System administrator', 1),
  ('viewer', 'arn:iam:123456789:role/viewer', 'Read-only access', 1),
  ('editor', 'arn:iam:123456789:role/editor', 'Read and write access', 1);

-- 插入默认策略
INSERT INTO `iam_policy` (`name`, `arn`, `policy_doc`, `policy_type`) VALUES
  ('AdminFullAccess', 'arn:iam:123456789:policy/AdminFullAccess',
   '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}', 'managed'),
  ('ReadOnlyAccess', 'arn:iam:123456789:policy/ReadOnlyAccess',
   '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["Get","Describe","List"],"Resource":"*"}]}', 'managed'),
  ('EditorAccess', 'arn:iam:123456789:policy/EditorAccess',
   '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["Get","Describe","List","Edit","Create","Update"],"Resource":"*"}]}', 'managed');

-- admin 角色绑定 AdminFullAccess 策略
INSERT INTO `iam_role_policy` (`role_id`, `policy_id`) VALUES (1, 1);
-- viewer 角色绑定 ReadOnlyAccess 策略
INSERT INTO `iam_role_policy` (`role_id`, `policy_id`) VALUES (2, 2);
-- editor 角色绑定 EditorAccess 策略
INSERT INTO `iam_role_policy` (`role_id`, `policy_id`) VALUES (3, 3);
