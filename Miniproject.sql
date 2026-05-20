
-- PHẦN 1: KHỞI TẠO CƠ SỞ DỮ LIỆU & CẤU TRÚC BẢNG (SCHEMA)

CREATE DATABASE IF NOT EXISTS social_network_db;
USE social_network_db;

-- Xóa các bảng cũ nếu tồn tại 
DROP TABLE IF EXISTS post_logs;
DROP TABLE IF EXISTS friends;
DROP TABLE IF EXISTS likes;
DROP TABLE IF EXISTS comments;
DROP TABLE IF EXISTS posts;
DROP TABLE IF EXISTS users;

-- 1. Bảng Users (Bảng cha)
CREATE TABLE users (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. Bảng Posts (Bảng con của users, bảng cha của likes/comments)
CREATE TABLE posts (
    post_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    content TEXT NOT NULL,
    like_count INT DEFAULT 0,
    comment_count INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id) -- Tuyệt đối không dùng ON DELETE CASCADE
);

-- Cài đặt Full-Text Search trên cột content của bảng posts để tối ưu tìm kiếm
ALTER TABLE posts ADD FULLTEXT INDEX idx_posts_content (content);

-- 3. Bảng Comments (Bảng con phụ thuộc posts và users)
CREATE TABLE comments (
    comment_id INT AUTO_INCREMENT PRIMARY KEY,
    post_id INT NOT NULL,
    user_id INT NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (post_id) REFERENCES posts(post_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

-- 4. Bảng Likes (Bảng con phụ thuộc posts và users)
CREATE TABLE likes (
    like_id INT AUTO_INCREMENT PRIMARY KEY,
    post_id INT NOT NULL,
    user_id INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (post_id) REFERENCES posts(post_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    -- Ràng buộc: Mỗi người chỉ được like một bài viết tối đa một lần
    CONSTRAINT unique_user_post_like UNIQUE (user_id, post_id)
);

-- 5. Bảng Friends (Bảng quản lý quan hệ bạn bè giữa các users)
CREATE TABLE friends (
    friendship_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    friend_id INT NOT NULL,
    status VARCHAR(20) DEFAULT 'pending', -- Trạng thái: pending, accepted
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (friend_id) REFERENCES users(user_id)
);

-- 6. Bảng Post Logs (Bảng lưu vết phục vụ yêu cầu mở nâng cao)
CREATE TABLE post_logs (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    post_id INT NOT NULL,
    post_content TEXT NOT NULL,
    deleted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- -------------------------------------------------------------------------
-- PHẦN 2: CHỨC NĂNG 1 - KHUNG NHÌN HỒ SƠ (VIEW)
-- -------------------------------------------------------------------------
-- Mục đích: Đổ dữ liệu an toàn, ẩn cột password để tránh rò rỉ thông tin
CREATE OR REPLACE VIEW view_user_info AS
SELECT user_id, username, email, created_at
FROM users;



-- PHẦN 3: ĐỊNH NGHĨA CÁC THỦ TỤC & TRIGGER (STORED PROCEDURES & TRIGGERS)

DELIMITER $$

-- CHỨC NĂNG 2: Thủ tục đăng ký tài khoản (sp_add_user)
CREATE PROCEDURE sp_add_user(
    IN p_username VARCHAR(50),
    IN p_password VARCHAR(255),
    IN p_email VARCHAR(100)
)
BEGIN
    -- Kiểm tra trùng lặp email và username trước khi thêm mới
    IF EXISTS (SELECT 1 FROM users WHERE email = p_email) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Lỗi nghiệp vụ: Email này đã được đăng ký hệ thống.';
    ELSEIF EXISTS (SELECT 1 FROM users WHERE username = p_username) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Lỗi nghiệp vụ: Tên tài khoản (username) đã tồn tại.';
    ELSE
        -- Hợp lệ tiến hành INSERT dữ liệu mới
        INSERT INTO users (username, password, email) 
        VALUES (p_username, p_password, p_email);
    END IF;
END$$


-- CHỨC NĂNG 3: Tự động tăng số lượt like khi chèn bản ghi vào bảng likes
CREATE TRIGGER tg_after_like_insert
AFTER INSERT ON likes
FOR EACH ROW
BEGIN
    UPDATE posts 
    SET like_count = like_count + 1 
    WHERE post_id = NEW.post_id;
END$$

-- CHỨC NĂNG 3: Tự động giảm số lượt like khi xóa bản ghi (Chặn không âm dưới 0)
CREATE TRIGGER tg_after_like_delete
AFTER DELETE ON likes
FOR EACH ROW
BEGIN
    UPDATE posts 
    SET like_count = IF(like_count > 0, like_count - 1, 0) 
    WHERE post_id = OLD.post_id;
END$$

-- CHỨC NĂNG 3: Tự động tăng số lượt bình luận khi chèn vào bảng comments
CREATE TRIGGER tg_after_comment_insert
AFTER INSERT ON comments
FOR EACH ROW
BEGIN
    UPDATE posts 
    SET comment_count = comment_count + 1 
    WHERE post_id = NEW.post_id;
END$$

-- CHỨC NĂNG 3: Tự động giảm số lượt bình luận khi xóa bản ghi (Chặn không âm dưới 0)
CREATE TRIGGER tg_after_comment_delete
AFTER DELETE ON comments
FOR EACH ROW
BEGIN
    UPDATE posts 
    SET comment_count = IF(comment_count > 0, comment_count - 1, 0) 
    WHERE post_id = OLD.post_id;
END$$


-- CHỨC NĂNG 4: Thủ tục Thống kê hoạt động của từng User (sp_user_activity_report)
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


-- CHỨC NĂNG 5: Thủ tục xóa tài khoản toàn vẹn dữ liệu sử dụng Transaction (sp_delete_user)
CREATE PROCEDURE sp_delete_user(IN p_user_id INT)
BEGIN
    -- Khai báo khối xử lý sự cố (Exit Handler) để Rollback khi có bất kì câu lệnh nào lỗi
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Giao dịch thất bại: Xung đột dữ liệu. Đã thực hiện ROLLBACK hệ thống.';
    END;

    -- Bắt đầu phiên giao dịch (Áp dụng nguyên tắc All-or-Nothing)
    START TRANSACTION;
        
        -- Bước 1: Xóa toàn bộ các lượt tương tác trong các bài viết thuộc về User sắp xóa
        DELETE FROM likes WHERE post_id IN (SELECT post_id FROM posts WHERE user_id = p_user_id);
        DELETE FROM comments WHERE post_id IN (SELECT post_id FROM posts WHERE user_id = p_user_id);

        -- Bước 2: Xóa toàn bộ các tương tác do CHÍNH người dùng này thực hiện trên bài viết người khác
        DELETE FROM likes WHERE user_id = p_user_id;
        DELETE FROM comments WHERE user_id = p_user_id;

        -- Bước 3: Xóa các mối quan hệ bạn bè của người dùng (Xử lý cả hai chiều)
        DELETE FROM friends WHERE user_id = p_user_id OR friend_id = p_user_id;

        -- Bước 4: Xóa các bài đăng thuộc quyền sở hữu của người dùng này
        DELETE FROM posts WHERE user_id = p_user_id;

        -- Bước 5: Tiến hành xóa bản ghi gốc tại bảng cha (users)
        DELETE FROM users WHERE user_id = p_user_id;

    -- Lưu lại mọi thay đổi vào cơ sở dữ liệu nếu chuỗi xử lý trên hoàn tất thành công
    COMMIT;
END$$


-- CHỨC NĂNG 6: Trigger kiểm soát logic kết bạn trước khi INSERT dữ liệu (tg_before_friend_insert)
CREATE TRIGGER tg_before_friend_insert
BEFORE INSERT ON friends
FOR EACH ROW
BEGIN
    -- Kiểm tra lỗi số 1: Tự gửi kết bạn cho chính mình
    IF NEW.user_id = NEW.friend_id THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Lỗi nghiệp vụ: Bạn không thể tự kết bạn với chính bản thân mình.';
    
    -- Kiểm tra lỗi số 2: Trùng lặp dữ liệu (Cặp quan hệ này đã tồn tại sẵn trong hệ thống)
    ELSEIF EXISTS (SELECT 1 FROM friends WHERE user_id = NEW.user_id AND friend_id = NEW.friend_id) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Lỗi nghiệp vụ: Lời mời hoặc mối quan hệ bạn bè này đã tồn tại trước đó.';
        
    -- Kiểm tra lỗi số 3: Lời mời đảo chiều (Đối phương đã gửi lời mời cho bạn từ trước, hệ thống đang chờ duyệt)
    ELSEIF EXISTS (SELECT 1 FROM friends WHERE user_id = NEW.friend_id AND friend_id = NEW.user_id) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Lỗi nghiệp vụ: Người dùng này đã gửi lời mời cho bạn rồi. Vui lòng chấp nhận thay vì tạo mới.';
    END IF;
END$$


-- YÊU CẦU MỞ RỘNG (NÂNG CAO): Nhật ký lưu vết khi xóa bài viết (tg_after_post_delete)
CREATE TRIGGER tg_after_post_delete
AFTER DELETE ON posts
FOR EACH ROW
BEGIN
    -- Sao chép tự động thông tin bài viết bị xóa vĩnh viễn vào bảng lưu vết post_logs
    INSERT INTO post_logs (post_id, post_content, deleted_at)
    VALUES (OLD.post_id, OLD.content, NOW());
END$$

DELIMITER ;


-- -------------------------------------------------------------------------
-- PHẦN 4: NẠP DỮ LIỆU MẪU (MOCK DATA) & KỊCH BẢN KIỂM THỬ HỆ THỐNG
-- -------------------------------------------------------------------------

-- 1. Nạp người dùng bằng Stored Procedure vừa tạo (Kiểm tra chức năng 2)
CALL sp_add_user('nguyen_van_a', 'matkhau123', 'anv@gmail.com');
CALL sp_add_user('tran_thi_b', 'matkhau456', 'btt@gmail.com');
CALL sp_add_user('le_van_c', 'matkhau789', 'clv@gmail.com');

-- [Kiểm thử Chức năng 1]: Kiểm tra View xem thông tin có bị lộ mật khẩu không
SELECT * FROM view_user_info;

-- [Kiểm thử Chức năng 2 bổ sung]: Thử đăng ký trùng Email xem hệ thống có báo lỗi chặn lại không
-- CALL sp_add_user('user_trung_lap', 'matkhauXYZ', 'anv@gmail.com');

-- 2. Thêm dữ liệu bài đăng ( posts ) mẫu để chuẩn bị test trigger đếm
-- (Giả định các ID tự tăng sinh ra lần lượt là 1, 2, 3)
INSERT INTO posts (user_id, content) VALUES 
(1, 'Hôm nay trời đẹp quá, cùng đi học cơ sở dữ liệu nào các bạn ơi!'),
(2, 'Dự án Mini Project MySQL này cấu hình trigger viết khá phức tạp.'),
(3, 'Tìm kiếm bài viết bằng công nghệ Full-text Search trên MySQL rất tối ưu.');

-- 3. Thực hiện hành vi Tương tác (Like & Bình luận) mẫu
INSERT INTO likes (user_id, post_id) VALUES (2, 1); -- User 2 like bài 1
INSERT INTO likes (user_id, post_id) VALUES (3, 1); -- User 3 like bài 1
INSERT INTO comments (post_id, user_id, content) VALUES (1, 2, 'Bài viết rất hay và ý nghĩa!'); -- User 2 comment bài 1

-- [Kiểm thử Chức năng 3]: Kiểm tra xem bộ đếm tương tác tự cộng (+1) lên nhờ Trigger chưa
SELECT post_id, content, like_count, comment_count FROM posts;

-- Thử hủy lượt thích (Xóa bản ghi bảng con) để kiểm tra trigger giảm bộ đếm (-1)
DELETE FROM likes WHERE user_id = 3 AND post_id = 1;
SELECT post_id, content, like_count FROM posts WHERE post_id = 1; -- Like_count từ 2 giảm xuống 1

-- [Kiểm thử Ràng buộc UNIQUE của bảng Likes]: Thử like trùng lặp lại (Sẽ báo lỗi từ MySQL)
-- INSERT INTO likes (user_id, post_id) VALUES (2, 1);

-- 4. Thử nghiệm kết bạn (Kiểm thử Chức năng 6)
INSERT INTO friends (user_id, friend_id, status) VALUES (1, 2, 'pending'); -- User 1 gửi kết bạn User 2 thành công

-- [Kiểm thử Chức năng 6 - Lỗi 1]: Tự kết bạn với chính mình (Sẽ vấp lỗi báo về từ Trigger)
-- INSERT INTO friends (user_id, friend_id) VALUES (1, 1);

--  Lời mời đảo chiều (User 2 gửi ngược cho User 1 trong khi đang pending)
-- INSERT INTO friends (user_id, friend_id) VALUES (2, 1);

-- 5. Chạy báo cáo thống kê hoạt động (Kiểm thử Chức năng 4)
CALL sp_user_activity_report();

-- 6. Kiểm thử quy trình xóa sạch dữ liệu liên kết bằng Transaction (Kiểm thử Chức năng 5 & Mở rộng)
-- Tiến hành xóa vĩnh viễn tài khoản của User số 3 (le_van_c)
CALL sp_delete_user(3);

-- Kiểm tra xem tài khoản User 3 đã biến mất hoàn toàn khỏi bảng Users chưa
SELECT * FROM users;

-- [Kiểm thử Yêu cầu Mở rộng]: Kiểm tra bảng Nhật ký `post_logs` xem bài đăng số 3 của User 3 có được sao lưu tự động chưa
SELECT * FROM post_logs;