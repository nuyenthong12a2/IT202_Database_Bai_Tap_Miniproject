DROP DATABASE IF EXISTS mini_social_network;
CREATE DATABASE mini_social_network;
USE mini_social_network;

-- =========================
-- 1. TABLES
-- =========================

CREATE TABLE users (
    user_id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;

CREATE TABLE posts (
    post_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    content TEXT NOT NULL,
    like_count INT DEFAULT 0,
    comment_count INT DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_posts_user
        FOREIGN KEY (user_id) REFERENCES users(user_id),

    CONSTRAINT ck_like_count CHECK (like_count >= 0),
    CONSTRAINT ck_comment_count CHECK (comment_count >= 0),

    FULLTEXT INDEX idx_posts_content (content)
) ENGINE = InnoDB;

CREATE TABLE comments (
    comment_id INT PRIMARY KEY AUTO_INCREMENT,
    post_id INT NOT NULL,
    user_id INT NOT NULL,
    content TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_comments_post
        FOREIGN KEY (post_id) REFERENCES posts(post_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_comments_user
        FOREIGN KEY (user_id) REFERENCES users(user_id)
) ENGINE = InnoDB;

CREATE TABLE likes (
    like_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    post_id INT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_likes_user
        FOREIGN KEY (user_id) REFERENCES users(user_id),

    CONSTRAINT fk_likes_post
        FOREIGN KEY (post_id) REFERENCES posts(post_id)
        ON DELETE CASCADE,

    CONSTRAINT uq_user_post UNIQUE (user_id, post_id)
) ENGINE = InnoDB;

CREATE TABLE friends (
    friendship_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    friend_id INT NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_friends_user
        FOREIGN KEY (user_id) REFERENCES users(user_id),

    CONSTRAINT fk_friends_friend
        FOREIGN KEY (friend_id) REFERENCES users(user_id),

    CONSTRAINT ck_friend_status CHECK (status IN ('pending', 'accepted')),
    CONSTRAINT ck_not_self_friend CHECK (user_id <> friend_id)
) ENGINE = InnoDB;

-- Chặn A kết bạn B và B kết bạn A bị trùng
CREATE UNIQUE INDEX uq_friend_pair
ON friends (
    (LEAST(user_id, friend_id)),
    (GREATEST(user_id, friend_id))
);

CREATE TABLE post_logs (
    log_id INT PRIMARY KEY AUTO_INCREMENT,
    post_id INT,
    user_id INT,
    content TEXT,
    action_type VARCHAR(50),
    action_date DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;


-- =========================
-- 2. TRIGGERS
-- =========================

DELIMITER $$

CREATE TRIGGER trg_after_like_insert
AFTER INSERT ON likes
FOR EACH ROW
BEGIN
    UPDATE posts
    SET like_count = like_count + 1
    WHERE post_id = NEW.post_id;
END $$

CREATE TRIGGER trg_after_like_delete
AFTER DELETE ON likes
FOR EACH ROW
BEGIN
    UPDATE posts
    SET like_count = like_count - 1
    WHERE post_id = OLD.post_id;
END $$

CREATE TRIGGER trg_after_comment_insert
AFTER INSERT ON comments
FOR EACH ROW
BEGIN
    UPDATE posts
    SET comment_count = comment_count + 1
    WHERE post_id = NEW.post_id;
END $$

CREATE TRIGGER trg_after_comment_delete
AFTER DELETE ON comments
FOR EACH ROW
BEGIN
    UPDATE posts
    SET comment_count = comment_count - 1
    WHERE post_id = OLD.post_id;
END $$

CREATE TRIGGER trg_before_post_delete
BEFORE DELETE ON posts
FOR EACH ROW
BEGIN
    INSERT INTO post_logs(post_id, user_id, content, action_type)
    VALUES (OLD.post_id, OLD.user_id, OLD.content, 'DELETE');
END $$

DELIMITER ;


-- =========================
-- 3. STORED PROCEDURES
-- =========================

DELIMITER $$

-- F01: Đăng ký user
CREATE PROCEDURE sp_register_user(
    IN p_username VARCHAR(50),
    IN p_password VARCHAR(255),
    IN p_email VARCHAR(100)
)
BEGIN
    INSERT INTO users(username, password, email)
    VALUES (p_username, SHA2(p_password, 256), p_email);
END $$


-- F02: Đăng bài viết
CREATE PROCEDURE sp_create_post(
    IN p_user_id INT,
    IN p_content TEXT
)
BEGIN
    INSERT INTO posts(user_id, content)
    VALUES (p_user_id, p_content);
END $$


-- F03: Like bài viết
CREATE PROCEDURE sp_like_post(
    IN p_user_id INT,
    IN p_post_id INT
)
BEGIN
    INSERT INTO likes(user_id, post_id)
    VALUES (p_user_id, p_post_id);
END $$


-- F03: Hủy like bài viết
CREATE PROCEDURE sp_unlike_post(
    IN p_user_id INT,
    IN p_post_id INT
)
BEGIN
    DELETE FROM likes
    WHERE user_id = p_user_id
      AND post_id = p_post_id;
END $$


-- F04: Gửi lời mời kết bạn
CREATE PROCEDURE sp_send_friend_request(
    IN p_user_id INT,
    IN p_friend_id INT
)
BEGIN
    INSERT INTO friends(user_id, friend_id, status)
    VALUES (p_user_id, p_friend_id, 'pending');
END $$


-- F05: Chấp nhận lời mời kết bạn
CREATE PROCEDURE sp_accept_friend_request(
    IN p_friendship_id INT
)
BEGIN
    UPDATE friends
    SET status = 'accepted'
    WHERE friendship_id = p_friendship_id;
END $$


-- F05: Hủy kết bạn / hủy lời mời
CREATE PROCEDURE sp_remove_friend(
    IN p_user_id INT,
    IN p_friend_id INT
)
BEGIN
    DELETE FROM friends
    WHERE (user_id = p_user_id AND friend_id = p_friend_id)
       OR (user_id = p_friend_id AND friend_id = p_user_id);
END $$


-- F08: Báo cáo hoạt động của user
CREATE PROCEDURE sp_user_activity_report(
    IN p_user_id INT
)
BEGIN
    SELECT 
        u.user_id,
        u.username,
        COUNT(DISTINCT p.post_id) AS total_posts,
        COALESCE(SUM(p.like_count), 0) AS total_likes,
        COALESCE(SUM(p.comment_count), 0) AS total_comments
    FROM users u
    LEFT JOIN posts p ON u.user_id = p.user_id
    WHERE u.user_id = p_user_id
    GROUP BY u.user_id, u.username;
END $$


-- F09: Gợi ý kết bạn - bạn của bạn
CREATE PROCEDURE sp_suggest_friends(
    IN p_user_id INT
)
BEGIN
    WITH my_friends AS (
        SELECT 
            CASE 
                WHEN user_id = p_user_id THEN friend_id
                ELSE user_id
            END AS friend_id
        FROM friends
        WHERE status = 'accepted'
          AND (user_id = p_user_id OR friend_id = p_user_id)
    ),
    friends_of_friends AS (
        SELECT 
            CASE 
                WHEN f.user_id = mf.friend_id THEN f.friend_id
                ELSE f.user_id
            END AS suggested_user_id
        FROM friends f
        JOIN my_friends mf
            ON f.user_id = mf.friend_id OR f.friend_id = mf.friend_id
        WHERE f.status = 'accepted'
    )
    SELECT DISTINCT 
        u.user_id,
        u.username,
        u.email
    FROM friends_of_friends fof
    JOIN users u ON u.user_id = fof.suggested_user_id
    WHERE fof.suggested_user_id <> p_user_id
      AND fof.suggested_user_id NOT IN (
          SELECT friend_id FROM my_friends
      );
END $$


-- F10: Xóa bài viết của chính mình
CREATE PROCEDURE sp_delete_own_post(
    IN p_user_id INT,
    IN p_post_id INT
)
BEGIN
    START TRANSACTION;

    DELETE FROM posts
    WHERE post_id = p_post_id
      AND user_id = p_user_id;

    COMMIT;
END $$


-- F11: Xóa tài khoản user an toàn bằng transaction
CREATE PROCEDURE sp_delete_user_account(
    IN p_user_id INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    DELETE FROM likes
    WHERE user_id = p_user_id;

    DELETE FROM comments
    WHERE user_id = p_user_id;

    DELETE FROM friends
    WHERE user_id = p_user_id
       OR friend_id = p_user_id;

    DELETE FROM posts
    WHERE user_id = p_user_id;

    DELETE FROM users
    WHERE user_id = p_user_id;

    COMMIT;
END $$

DELIMITER ;


-- =========================
-- 4. VIEWS
-- =========================

CREATE VIEW v_user_profile AS
SELECT 
    u.user_id,
    u.username,
    u.email,
    u.created_at,
    COUNT(DISTINCT p.post_id) AS total_posts,
    COALESCE(SUM(p.like_count), 0) AS total_likes,
    COALESCE(SUM(p.comment_count), 0) AS total_comments
FROM users u
LEFT JOIN posts p ON u.user_id = p.user_id
GROUP BY u.user_id, u.username, u.email, u.created_at;


CREATE VIEW v_post_detail AS
SELECT 
    p.post_id,
    p.content,
    p.like_count,
    p.comment_count,
    p.created_at,
    u.user_id,
    u.username
FROM posts p
JOIN users u ON p.user_id = u.user_id;


-- =========================
-- 5. SAMPLE DATA
-- =========================

CALL sp_register_user('tung', '123456', 'tung@gmail.com');
CALL sp_register_user('nam', '123456', 'nam@gmail.com');
CALL sp_register_user('linh', '123456', 'linh@gmail.com');
CALL sp_register_user('hoa', '123456', 'hoa@gmail.com');

CALL sp_create_post(1, 'Hello mọi người, đây là bài viết đầu tiên.');
CALL sp_create_post(1, 'Hôm nay học MySQL Trigger và Transaction.');
CALL sp_create_post(2, 'Database rất quan trọng trong backend.');
CALL sp_create_post(3, 'Ai học SQL không?');

CALL sp_like_post(2, 1);
CALL sp_like_post(3, 1);
CALL sp_like_post(4, 1);
CALL sp_like_post(1, 3);

INSERT INTO comments(post_id, user_id, content)
VALUES
(1, 2, 'Bài viết hay quá!'),
(1, 3, 'Tui cũng đang học SQL.'),
(3, 1, 'Chuẩn luôn bạn.');

CALL sp_send_friend_request(1, 2);
CALL sp_send_friend_request(1, 3);
CALL sp_send_friend_request(2, 4);

CALL sp_accept_friend_request(1);
CALL sp_accept_friend_request(2);
CALL sp_accept_friend_request(3);


-- =========================
-- 6. TEST QUERIES
-- =========================

SELECT * FROM users;
SELECT * FROM posts;
SELECT * FROM likes;
SELECT * FROM comments;
SELECT * FROM friends;
SELECT * FROM v_user_profile;
SELECT * FROM v_post_detail;

-- Tìm kiếm bài viết theo từ khóa
SELECT *
FROM posts
WHERE MATCH(content) AGAINST('SQL' IN NATURAL LANGUAGE MODE);

-- Báo cáo user
CALL sp_user_activity_report(1);

-- Gợi ý kết bạn
CALL sp_suggest_friends(1);

-- Test hủy like
CALL sp_unlike_post(2, 1);

-- Test xóa bài viết
CALL sp_delete_own_post(1, 2);

-- Xem log xóa bài viết
SELECT * FROM post_logs;