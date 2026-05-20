-- 1. TẠO CẤU TRÚC BẢNG
CREATE TABLE users (
    user_id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE posts (
    post_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    content TEXT,
    like_count INT DEFAULT 0,
    comment_count INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FULLTEXT(content)
);

CREATE TABLE likes (
    like_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    post_id INT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (post_id) REFERENCES posts(post_id),
    UNIQUE(user_id, post_id)
);

CREATE TABLE comments (
    comment_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    post_id INT NOT NULL,
    content TEXT,
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (post_id) REFERENCES posts(post_id)
);

CREATE TABLE friends (
    friendship_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    friend_id INT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (friend_id) REFERENCES users(user_id)
);

CREATE TABLE post_logs (
    log_id INT PRIMARY KEY AUTO_INCREMENT,
    post_id INT,
    post_content TEXT,
    deleted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. VIEW
CREATE OR REPLACE VIEW view_user_info AS
SELECT user_id, username, email, created_at FROM users;

-- 3. STORED PROCEDURES & TRIGGERS
DELIMITER //

-- Đăng ký user
CREATE PROCEDURE sp_add_user(IN p_username VARCHAR(50), IN p_password VARCHAR(255), IN p_email VARCHAR(100))
BEGIN
    IF EXISTS (SELECT 1 FROM users WHERE username = p_username OR email = p_email) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Username hoặc Email đã tồn tại';
    ELSE
        INSERT INTO users (username, password, email) VALUES (p_username, p_password, p_email);
    END IF;
END //

-- Triggers tương tác
CREATE TRIGGER tg_after_like_insert AFTER INSERT ON likes
FOR EACH ROW UPDATE posts SET like_count = like_count + 1 WHERE post_id = NEW.post_id; //

CREATE TRIGGER tg_after_like_delete AFTER DELETE ON likes
FOR EACH ROW UPDATE posts SET like_count = IF(like_count > 0, like_count - 1, 0) WHERE post_id = OLD.post_id; //

CREATE TRIGGER tg_after_comment_insert AFTER INSERT ON comments
FOR EACH ROW UPDATE posts SET comment_count = comment_count + 1 WHERE post_id = NEW.post_id; //

CREATE TRIGGER tg_after_comment_delete AFTER DELETE ON comments
FOR EACH ROW UPDATE posts SET comment_count = IF(comment_count > 0, comment_count - 1, 0) WHERE post_id = OLD.post_id; //

-- Trigger Audit Log
CREATE TRIGGER tg_after_post_delete AFTER DELETE ON posts
FOR EACH ROW INSERT INTO post_logs (post_id, post_content) VALUES (OLD.post_id, OLD.content); //

-- Trigger kiểm soát bạn bè
CREATE TRIGGER tg_before_friend_insert BEFORE INSERT ON friends
FOR EACH ROW
BEGIN
    IF NEW.user_id = NEW.friend_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Không thể tự kết bạn';
    ELSEIF EXISTS (SELECT 1 FROM friends WHERE (user_id = NEW.user_id AND friend_id = NEW.friend_id) 
                    OR (user_id = NEW.friend_id AND friend_id = NEW.user_id)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Đã tồn tại quan hệ bạn bè';
    END IF;
END //

-- Procedure xóa user toàn vẹn
CREATE PROCEDURE sp_delete_user(IN p_user_id INT)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; END;
    START TRANSACTION;
        -- Xóa tương tác của bài viết do user tạo
        DELETE FROM likes WHERE post_id IN (SELECT post_id FROM posts WHERE user_id = p_user_id);
        DELETE FROM comments WHERE post_id IN (SELECT post_id FROM posts WHERE user_id = p_user_id);
        -- Xóa tương tác cá nhân của user
        DELETE FROM likes WHERE user_id = p_user_id;
        DELETE FROM comments WHERE user_id = p_user_id;
        -- Xóa quan hệ bạn bè
        DELETE FROM friends WHERE user_id = p_user_id OR friend_id = p_user_id;
        -- Xóa bài viết và user
        DELETE FROM posts WHERE user_id = p_user_id;
        DELETE FROM users WHERE user_id = p_user_id;
    COMMIT;
END //

-- Procedure thống kê
CREATE PROCEDURE sp_user_activity_report()
BEGIN
    SELECT u.user_id, u.username, 
           COUNT(DISTINCT p.post_id) AS post_count, 
           COUNT(DISTINCT l.like_id) AS like_count, 
           COUNT(DISTINCT c.comment_id) AS comment_count
    FROM users u
    LEFT JOIN posts p ON u.user_id = p.user_id
    LEFT JOIN likes l ON u.user_id = l.user_id
    LEFT JOIN comments c ON u.user_id = c.user_id
    GROUP BY u.user_id;
END //
DELIMITER ;

-- 4. DỮ LIỆU MẪU (TEST)
INSERT INTO users (username, password, email) VALUES ('alice', '123', 'alice@test.com'), ('bob', '123', 'bob@test.com'), ('charlie', '123', 'charlie@test.com');
INSERT INTO posts (user_id, content) VALUES (1, 'Hello World'), (2, 'MySQL is fun'), (3, 'Learning database');
INSERT INTO likes (user_id, post_id) VALUES (1, 2), (2, 3), (3, 1);
INSERT INTO comments (user_id, post_id, content) VALUES (2, 1, 'Nice post!'), (3, 2, 'Agree!');
INSERT INTO friends (user_id, friend_id) VALUES (1, 2);