-- 1. KHOI TAO DATABASE
CREATE DATABASE IF NOT EXISTS mini_social_network;
USE mini_social_network;

-- 2. SCHEMA (Cấu trúc bảng)
CREATE TABLE users (
    user_id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE posts (
    post_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT,
    content TEXT NOT NULL,
    like_count INT DEFAULT 0,
    comment_count INT DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
) ENGINE=InnoDB;

CREATE TABLE comments (
    comment_id INT PRIMARY KEY AUTO_INCREMENT,
    post_id INT,
    user_id INT,
    content TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (post_id) REFERENCES posts(post_id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
) ENGINE=InnoDB;

CREATE TABLE friends (
    friendship_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT,
    friend_id INT,
    status VARCHAR(20) CHECK (status IN ('pending', 'accepted')),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (friend_id) REFERENCES users(user_id),
    CONSTRAINT check_self_friend CHECK (user_id != friend_id),
    UNIQUE (LEAST(user_id, friend_id), GREATEST(user_id, friend_id))
) ENGINE=InnoDB;

CREATE TABLE likes (
    like_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT,
    post_id INT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (post_id) REFERENCES posts(post_id) ON DELETE CASCADE,
    UNIQUE (user_id, post_id)
) ENGINE=InnoDB;

-- 3. TRIGGER (F03, F04 - Tự động cập nhật thống kê)
DELIMITER //
CREATE TRIGGER after_like_insert AFTER INSERT ON likes
FOR EACH ROW BEGIN UPDATE posts SET like_count = like_count + 1 WHERE post_id = NEW.post_id; END //
CREATE TRIGGER after_like_delete AFTER DELETE ON likes
FOR EACH ROW BEGIN UPDATE posts SET like_count = like_count - 1 WHERE post_id = OLD.post_id; END //
CREATE TRIGGER after_comment_insert AFTER INSERT ON comments
FOR EACH ROW BEGIN UPDATE posts SET comment_count = comment_count + 1 WHERE post_id = NEW.post_id; END //
CREATE TRIGGER after_comment_delete AFTER DELETE ON comments
FOR EACH ROW BEGIN UPDATE posts SET comment_count = comment_count - 1 WHERE post_id = OLD.post_id; END //
DELIMITER ;

-- 4. STORED PROCEDURES (Đủ F01 - F11)
DELIMITER //
-- F01: Đăng ký
CREATE PROCEDURE register_user(IN p_username VARCHAR(50), IN p_password VARCHAR(255), IN p_email VARCHAR(100))
BEGIN INSERT INTO users (username, password, email) VALUES (p_username, p_password, p_email); END //

-- F02: Đăng bài
CREATE PROCEDURE create_post(IN p_user_id INT, IN p_content TEXT)
BEGIN INSERT INTO posts (user_id, content) VALUES (p_user_id, p_content); END //

-- F03: Like/Unlike
CREATE PROCEDURE toggle_like(IN p_uid INT, IN p_pid INT)
BEGIN
    DECLARE v_id INT;
    SELECT like_id INTO v_id FROM likes WHERE user_id = p_uid AND post_id = p_pid;
    IF v_id IS NULL THEN INSERT INTO likes (user_id, post_id) VALUES (p_uid, p_pid);
    ELSE DELETE FROM likes WHERE like_id = v_id; END IF;
END //

-- F04/F05: Kết bạn
CREATE PROCEDURE manage_friendship(IN p_uid INT, IN p_fid INT, IN p_act VARCHAR(10))
BEGIN
    IF p_act = 'add' THEN INSERT INTO friends (user_id, friend_id, status) VALUES (p_uid, p_fid, 'pending');
    ELSEIF p_act = 'accept' THEN UPDATE friends SET status = 'accepted' WHERE user_id = p_fid AND friend_id = p_uid;
    END IF;
END //

-- F08: Báo cáo
CREATE PROCEDURE get_user_stats(IN p_uid INT)
BEGIN
    SELECT count(p.post_id) as total_posts, sum(p.like_count) as total_likes_received, count(c.comment_id) as total_comments
    FROM posts p LEFT JOIN comments c ON p.post_id = c.post_id WHERE p.user_id = p_uid;
END //

-- F11: Xóa tài khoản (Transaction đảm bảo ACID)
CREATE PROCEDURE delete_account(IN p_uid INT)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; END;
    START TRANSACTION;
    DELETE FROM likes WHERE user_id = p_uid;
    DELETE FROM comments WHERE user_id = p_uid;
    DELETE FROM friends WHERE user_id = p_uid OR friend_id = p_uid;
    DELETE FROM posts WHERE user_id = p_uid;
    DELETE FROM users WHERE user_id = p_uid;
    COMMIT;
END //
DELIMITER ;

-- 5. DU LIEU MAU
INSERT INTO users (username, password, email) VALUES ('thong', '123', 'a@a.com'), ('hao', '123', 'b@b.com');
CALL create_post(1, 'Hello World');
CALL toggle_like(2, 1);