-- =========================================================================
-- MINI PROJECT: CƠ SỞ DỮ LIỆU "SOCIAL NETWORK" (BẢN CHUẨN ĐÚNG ĐỀ BÀI)
-- TOÀN BỘ KỊCH BẢN SQL TRÊN MỘT FILE DUY NHẤT - CHẠY LÀ ĐƯỢC
-- =========================================================================

-- -------------------------------------------------------------------------
-- 2. QUY CHUẨN KỸ THUẬT CHUNG: KHỞI TẠO CƠ SỞ DỮ LIỆU & BẢNG (SCHEMA)
-- -------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS social_network_db;
USE social_network_db;

-- Dọn dẹp dữ liệu cũ nếu có để tránh lỗi trùng lặp khi chạy lại file
DROP TABLE IF EXISTS post_logs;
DROP TABLE IF EXISTS friends;
DROP TABLE IF EXISTS likes;
DROP TABLE IF EXISTS comments;
DROP TABLE IF EXISTS posts;
DROP TABLE IF EXISTS users;

-- [Quy chuẩn đặt tên]: 100% sử dụng snake_case
-- [Toàn vẹn tham chiếu]: Khởi tạo Foreign Key đầy đủ, TUYỆT ĐỐI KHÔNG dùng ON DELETE CASCADE

CREATE TABLE users (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE posts (
    post_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    content TEXT NOT NULL,
    like_count INT DEFAULT 0,
    comment_count INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

-- [Chỉ mục (Index)]: Cài đặt Full-Text Search trên cột content của bảng posts
ALTER TABLE posts ADD FULLTEXT INDEX idx_posts_content (content);

CREATE TABLE comments (
    comment_id INT AUTO_INCREMENT PRIMARY KEY,
    post_id INT NOT NULL,
    user_id INT NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (post_id) REFERENCES posts(post_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

CREATE TABLE likes (
    like_id INT AUTO_INCREMENT PRIMARY KEY,
    post_id INT NOT NULL,
    user_id INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (post_id) REFERENCES posts(post_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    -- [Ràng buộc Dữ liệu]: Mỗi người chỉ like 1 bài viết 1 lần
    CONSTRAINT unique_user_post_like UNIQUE (user_id, post_id)
);

CREATE TABLE friends (
    friendship_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    friend_id INT NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (friend_id) REFERENCES users(user_id)
);

-- [4. Yêu cầu Mở rộng]: Khởi tạo bảng nhật ký lưu vết post_logs
CREATE TABLE post_logs (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    post_id INT NOT NULL,
    post_content TEXT NOT NULL,
    deleted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- -------------------------------------------------------------------------
-- 3. ĐẶC TẢ CHỨC NĂNG CHI TIẾT
-- -------------------------------------------------------------------------

-- >>> CHỨC NĂNG 1: Khung nhìn Hồ sơ (view_user_info)
-- Yêu cầu: Không chứa password để tránh rò rỉ dữ liệu
CREATE OR REPLACE VIEW view_user_info AS
SELECT user_id, username, email, created_at
FROM users;


DELIMITER $$

-- >>> CHỨC NĂNG 2: Đăng ký tài khoản (sp_add_user)
-- Yêu cầu: Kiểm tra trùng lặp email và username. Hợp lệ -> INSERT, tồn tại -> Báo lỗi.
CREATE PROCEDURE sp_add_user(
    IN p_username VARCHAR(50),
    IN p_password VARCHAR(255),
    IN p_email VARCHAR(100)
)
BEGIN
    IF EXISTS (SELECT 1 FROM users WHERE email = p_email) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Lỗi: Email này đã được đăng ký hệ thống.';
    ELSEIF EXISTS (SELECT 1 FROM users WHERE username = p_username) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Lỗi: Tên tài khoản (username) đã tồn tại.';
    ELSE
        INSERT INTO users (username, password, email) 
        VALUES (p_username, p_password, p_email);
    END IF;
END$$


-- >>> CHỨC NĂNG 3: Tự động đếm tương tác (Các Trigger cộng trừ bộ đếm)
-- Ràng buộc: Trigger DELETE phải chặn không cho phép giá trị đếm bị giảm xuống dưới 0.

-- 1. tg_after_like_insert
CREATE TRIGGER tg_after_like_insert
AFTER INSERT ON likes
FOR EACH ROW
BEGIN
    UPDATE posts SET like_count = like_count + 1 WHERE post_id = NEW.post_id;
END$$

-- 2. tg_after_like_delete
CREATE TRIGGER tg_after_like_delete
AFTER DELETE ON likes
FOR EACH ROW
BEGIN
    UPDATE posts SET like_count = IF(like_count > 0, like_count - 1, 0) WHERE post_id = OLD.post_id;
END$$

-- 3. tg_after_comment_insert
CREATE TRIGGER tg_after_comment_insert
AFTER INSERT ON comments
FOR EACH ROW
BEGIN
    UPDATE posts SET comment_count = comment_count + 1 WHERE post_id = NEW.post_id;
END$$

-- 4. tg_after_comment_delete
CREATE TRIGGER tg_after_comment_delete
AFTER DELETE ON comments
FOR EACH ROW
BEGIN
    UPDATE posts SET comment_count = IF(comment_count > 0, comment_count - 1, 0) WHERE post_id = OLD.post_id;
END$$


-- >>> CHỨC NĂNG 4: Thống kê hoạt động (sp_user_activity_report)
-- Yêu cầu: Dùng COUNT, GROUP BY qua 4 bảng. Bắt buộc dùng LEFT JOIN để user mới vẫn hiển thị giá trị 0.
CREATE PROCEDURE sp_user_activity_report()
BEGIN
    SELECT 
        u.user_id,
        u.username,
        COUNT(DISTINCT p.post_id) AS total_posts,
        COUNT(DISTINCT l.like_id) AS total_likes_given,
        COUNT(DISTINCT c.comment_id) AS total_comments_written
    FROM users u
    LEFT JOIN posts p ON u.user_id = p.user_id
    LEFT JOIN likes l ON u.user_id = l.user_id
    LEFT JOIN comments c ON u.user_id = c.user_id
    GROUP BY u.user_id, u.username;
END$$


-- >>> CHỨC NĂNG 5: Xóa tài khoản toàn vẹn (sp_delete_user)
-- Yêu cầu: Mở TRANSACTION. Xóa thủ công từ bảng con ngược lên bảng cha. Thất bại phải ROLLBACK (All-or-Nothing).
CREATE PROCEDURE sp_delete_user(IN p_user_id INT)
BEGIN
    -- Cấu hình handler: Bất kỳ lệnh DELETE nào lỗi -> ROLLBACK ngay lập tức
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Giao dịch thất bại! Đã thực hiện ROLLBACK toàn bộ để bảo vệ toàn vẹn dữ liệu.';
    END;

    START TRANSACTION;
        
        -- Bước 1: Xóa các tương tác (like, comment) nằm TRÊN các bài viết của user sắp bị xóa trước
        DELETE FROM likes WHERE post_id IN (SELECT post_id FROM posts WHERE user_id = p_user_id);
        DELETE FROM comments WHERE post_id IN (SELECT post_id FROM posts WHERE user_id = p_user_id);

        -- Bước 2: Xóa các tương tác (like, comment) do chính user này đi thực hiện ở bài viết của người khác
        DELETE FROM likes WHERE user_id = p_user_id;
        DELETE FROM comments WHERE user_id = p_user_id;

        -- Bước 3: Xóa các mối quan hệ bạn bè (cả 2 chiều: gửi đi hoặc nhận về)
        DELETE FROM friends WHERE user_id = p_user_id OR friend_id = p_user_id;

        -- Bước 4: Xóa các bài viết (posts) do người dùng này đăng
        DELETE FROM posts WHERE user_id = p_user_id;

        -- Bước 5: Xóa bản ghi gốc tại bảng cha (users)
        DELETE FROM users WHERE user_id = p_user_id;

    COMMIT;
END$$


-- >>> CHỨC NĂNG 6: Kiểm soát kết bạn (tg_before_friend_insert)
-- Yêu cầu: SIGNAL SQLSTATE báo lỗi nếu: tự kết bạn, trùng lặp bản ghi, hoặc lời mời đảo chiều.
CREATE TRIGGER tg_before_friend_insert
BEFORE INSERT ON friends
FOR EACH ROW
BEGIN
    -- Lỗi 1: Tự kết bạn với chính mình
    IF NEW.user_id = NEW.friend_id THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Lỗi: Không thể tự gửi lời mời kết bạn cho chính mình.';
    
    -- Lỗi 2: Trùng lặp dữ liệu
    ELSEIF EXISTS (SELECT 1 FROM friends WHERE user_id = NEW.user_id AND friend_id = NEW.friend_id) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Lỗi: Cặp user_id và friend_id này đã tồn tại trong hệ thống.';
        
    -- Lỗi 3: Lời mời đảo chiều
    ELSEIF EXISTS (SELECT 1 FROM friends WHERE user_id = NEW.friend_id AND friend_id = NEW.user_id) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Lỗi: Đã tồn tại lời mời đảo chiều từ trước. Vui lòng phê duyệt lời mời thay vì tạo mới.';
    END IF;
END$$


-- >>> 4. YÊU CẦU MỞ RỘNG (NÂNG CAO): Nhật ký lưu vết (tg_after_post_delete)
-- Yêu cầu: Khi một bài viết bị xóa vĩnh viễn, tự động sao chép nội dung sang bảng post_logs.
CREATE TRIGGER tg_after_post_delete
AFTER DELETE ON posts
FOR EACH ROW
BEGIN
    INSERT INTO post_logs (post_id, post_content)
    VALUES (OLD.post_id, OLD.content);
END$$

DELIMITER ;


-- -------------------------------------------------------------------------
-- DỮ LIỆU MẪU (MOCK DATA) & KỊCH BẢN KIỂM THỬ HỆ THỐNG
-- -------------------------------------------------------------------------

-- 1. Thêm 3 người dùng mẫu qua Stored Procedure (Test Chức năng 2)
CALL sp_add_user('nguyen_van_a', 'pass123', 'anv@gmail.com');
CALL sp_add_user('tran_thi_b', 'pass456', 'btt@gmail.com');
CALL sp_add_user('le_van_c', 'pass789', 'clv@gmail.com');

-- [Kiểm tra Chức năng 1]: Xem View thông tin tài cá nhân (An toàn, không lộ mật khẩu)
SELECT * FROM view_user_info;

-- 2. Thêm 3 bài viết mẫu (Mỗi user đăng 1 bài)
INSERT INTO posts (user_id, content) VALUES 
(1, 'Học lập trình cơ sở dữ liệu MySQL rất thú vị và thực tế!'),
(2, 'Làm đồ án Mini Project cần nắm vững kiến thức về Transaction.'),
(3, 'Tối ưu hóa tìm kiếm văn bản bằng chỉ mục Full-Text Search.');

-- 3. Tạo các tương tác cơ bản (Like, Comment, Kết bạn)
INSERT INTO likes (user_id, post_id) VALUES (2, 1); -- User 2 thích bài viết 1
INSERT INTO likes (user_id, post_id) VALUES (3, 1); -- User 3 thích bài viết 1
INSERT INTO comments (post_id, user_id, content) VALUES (1, 2, 'Bài đăng này hay quá bạn ơi!'); -- User 2 comment bài viết 1

-- [Kiểm tra Chức năng 3]: Xem bộ đếm tương tác tự tăng trong bảng posts qua Trigger
SELECT post_id, content, like_count, comment_count FROM posts;

-- 4. Thử nghiệm kết bạn hợp lệ
INSERT INTO friends (user_id, friend_id, status) VALUES (1, 2, 'pending');

-- [Kiểm tra Chức năng 6]: Chạy thử các câu lệnh lỗi dưới đây (bằng cách bỏ dấu comment '--') để xem Trigger chặn lỗi
-- INSERT INTO friends (user_id, friend_id) VALUES (1, 1); -- Thử tự kết bạn -> Sẽ báo lỗi
-- INSERT INTO friends (user_id, friend_id) VALUES (2, 1); -- Thử gửi lời mời đảo chiều -> Sẽ báo lỗi

-- [Kiểm tra Chức năng 4]: Chạy báo cáo thống kê hoạt động tổng hợp của các User
CALL sp_user_activity_report();

-- [Kiểm tra Chức năng 5 & Nâng cao]: Tiến hành xóa tài khoản toàn vẹn cho User số 3 (le_van_c)
CALL sp_delete_user(3);

-- Xác nhận lại xem User 3 đã bị xóa sạch khỏi danh sách người dùng chưa
SELECT * FROM users;

-- Xác nhận bảng Nhật ký lưu vết xem bài đăng của User 3 đã được tự động sao lưu chưa
SELECT * FROM post_logs;