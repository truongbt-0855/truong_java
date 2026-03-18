# SUN Booking Tours — Task Checklist

> Stack: Spring Boot · Spring Data JPA · Spring Security · JWT · OAuth2 · PostgreSQL
> Roles: ADMIN (API + UI) · USER (API) · GUEST (API, anonymous)

---

## PHASE 1 — Project Foundation

### T01 — Project Setup
- [ ] Tạo project qua Spring Initializr (xem hướng dẫn bên dưới)
- [ ] Cấu hình `application.yml`: datasource, JPA, JWT secret/expiry, OAuth2 credentials
- [ ] Tạo package structure:
  ```
  com.sun.booking
  ├── config/
  ├── controller/
  ├── service/
  ├── repository/
  ├── entity/
  ├── dto/
  │   ├── request/
  │   └── response/
  ├── mapper/
  ├── security/
  ├── exception/
  └── util/
  ```
- [ ] Tạo `ApiResponse<T>` wrapper cho tất cả response
- [ ] Tạo `GlobalExceptionHandler` (`@RestControllerAdvice`)
- [ ] Tạo các custom exception: `ResourceNotFoundException`, `BusinessException`, `UnauthorizedException`
- [ ] Chạy `schema.sql` lên PostgreSQL (Flyway migration hoặc chạy tay)
- [ ] Verify kết nối DB thành công khi start app

---

## PHASE 2 — Auth & User

### T02 — JWT Authentication
- [ ] Thêm dependency `jjwt` vào `pom.xml`
- [ ] Tạo `JwtTokenProvider`: generate, validate, parse token
- [ ] Tạo `JwtAuthenticationFilter` (extends `OncePerRequestFilter`)
- [ ] Cấu hình `SecurityFilterChain`:
  - Public routes: `/api/auth/**`, `GET /api/tours/**`, `GET /api/places/**`, `GET /api/foods/**`, `GET /api/news/**`, `GET /api/reviews/**`, `GET /api/categories/**`
  - USER routes: `/api/bookings/**`, `/api/payments/**`, `/api/reviews/**` (POST/PUT/DELETE), `/api/comments/**`, `/api/users/me/**`
  - ADMIN routes: `/api/admin/**`
- [ ] `UserDetailsService` load user by email từ DB
- [ ] Tạo `UserPrincipal` (implements `UserDetails`)
- [ ] `POST /api/auth/register` — tạo user mới (role=USER, is_active=true)
- [ ] `POST /api/auth/login` — xác thực, trả `accessToken` + `refreshToken`
- [ ] `POST /api/auth/refresh` — validate refresh token, cấp access token mới
- [ ] `POST /api/auth/logout` — invalidate refresh token

### T03 — OAuth2 Login
- [ ] Thêm dependency `spring-boot-starter-oauth2-client`
- [ ] Cấu hình provider Google, Facebook, Twitter trong `application.yml`
- [ ] Implement `OAuth2UserService` (custom, load/create user từ OAuth profile)
- [ ] `OAuth2AuthenticationSuccessHandler`: sau login thành công → tạo JWT → redirect hoặc trả token
- [ ] Lưu vào bảng `oauth_accounts` (upsert theo provider + provider_user_id)
- [ ] Test flow: `GET /oauth2/authorize/{provider}` → callback → JWT

### T04 — User Profile
- [ ] `GET /api/users/me` — trả thông tin profile của user đang đăng nhập
- [ ] `PUT /api/users/me` — cập nhật `full_name`, `phone`, `avatar_url`
- [ ] `PUT /api/users/me/password` — đổi mật khẩu (validate old password trước)

### T05 — Bank Account
- [ ] `GET /api/users/me/bank-accounts` — list tài khoản ngân hàng
- [ ] `POST /api/users/me/bank-accounts` — thêm mới
- [ ] `PUT /api/users/me/bank-accounts/{id}` — cập nhật
- [ ] `DELETE /api/users/me/bank-accounts/{id}` — xóa (chỉ được xóa của mình)
- [ ] `PATCH /api/users/me/bank-accounts/{id}/default` — đặt làm mặc định (unset cái cũ)

---

## PHASE 3 — Category & Tour

### T06 — Category (Admin)
- [ ] Entity `Category` với self-reference `parent_id`
- [ ] `GET /api/categories` — list dạng tree (Guest + User)
- [ ] `POST /api/admin/categories` — tạo category
- [ ] `PUT /api/admin/categories/{id}` — cập nhật
- [ ] `DELETE /api/admin/categories/{id}` — xóa / deactivate (`is_active=false`)

### T07 — Tour CRUD (Admin)
- [ ] Entity `Tour`, `TourImage`, `TourPlace`, `TourFood`
- [ ] `POST /api/admin/tours` — tạo tour (status mặc định `DRAFT`)
- [ ] `PUT /api/admin/tours/{id}` — cập nhật thông tin tour
- [ ] `DELETE /api/admin/tours/{id}` — soft delete (`deleted_at = NOW()`)
- [ ] `PATCH /api/admin/tours/{id}/status` — chuyển status (`DRAFT`→`ACTIVE`→`INACTIVE`)
- [ ] `POST /api/admin/tours/{id}/images` — upload/thêm ảnh
- [ ] `DELETE /api/admin/tours/{id}/images/{imageId}` — xóa ảnh
- [ ] `PUT /api/admin/tours/{id}/places` — set danh sách places liên kết
- [ ] `PUT /api/admin/tours/{id}/foods` — set danh sách foods liên kết

### T08 — Tour Schedule (Admin)
- [ ] Entity `TourSchedule`
- [ ] `GET /api/admin/tours/{id}/schedules` — list schedules của tour
- [ ] `POST /api/admin/tours/{id}/schedules` — tạo lịch khởi hành
- [ ] `PUT /api/admin/schedules/{id}` — cập nhật lịch
- [ ] `PATCH /api/admin/schedules/{id}/status` — đổi status (`OPEN`/`FULL`/`CANCELLED`)

### T09 — Tour Public API (Guest + User)
- [ ] `GET /api/tours` — list tours (chỉ `status=ACTIVE`, `deleted_at IS NULL`)
  - Filter: `categoryId`, `minPrice`, `maxPrice`, `durationDays`, `departureLocation`
  - Pagination: `page`, `size`, `sort`
- [ ] `GET /api/tours/{slug}` — chi tiết tour (kèm images, schedules còn OPEN, places, foods)
- [ ] `GET /api/tours/search?q=` — tìm kiếm theo title, description, departure_location (LIKE hoặc full-text)

---

## PHASE 4 — Booking & Payment

### T10 — Booking (User)
- [ ] Entity `Booking`
- [ ] `POST /api/bookings` — tạo booking
  - [ ] Validate schedule `status=OPEN`
  - [ ] Validate còn đủ slot: `total_slots - SUM(num_participants của bookings CONFIRMED/PENDING) >= num_participants`
  - [ ] Tính `total_amount = num_participants × (price_override ?? tour.base_price)`
  - [ ] Sinh `booking_code` duy nhất (VD: `TOUR-YYYYMMDD-XXXXX`)
  - [ ] Lưu booking `status=PENDING`
  - [ ] Gọi `ActivityService.log(BOOKING_CREATED)`
- [ ] `GET /api/bookings` — danh sách booking của user (filter `status`, pagination)
- [ ] `GET /api/bookings/{id}` — chi tiết booking (chỉ của user đang đăng nhập)
- [ ] `POST /api/bookings/{id}/cancel` — hủy booking
  - [ ] Validate booking thuộc user, status phải là `PENDING` hoặc `CONFIRMED`
  - [ ] Set `status=CANCELLED`, `cancelled_at`, `cancel_reason`
  - [ ] Gọi `ActivityService.log(BOOKING_CANCELLED)`

### T11 — Payment (User)
- [ ] Entity `Payment`
- [ ] `POST /api/payments` — tạo payment
  - [ ] Validate booking thuộc user, booking `status=PENDING`
  - [ ] Validate `method=INTERNET_BANKING`
  - [ ] Validate `bank_account_id` tồn tại và thuộc user (nếu truyền lên)
  - [ ] Lưu payment `status=SUCCESS` (mock)
  - [ ] Update booking `status=CONFIRMED`
  - [ ] Gọi `ActivityService.log(PAYMENT_COMPLETED)`
- [ ] `GET /api/payments/{bookingId}` — xem thông tin payment của booking

---

## PHASE 5 — Review, Rating & Social

### T12 — Review (User)
- [ ] Entity `Review`
- [ ] `POST /api/reviews` — tạo review
  - [ ] Validate `target_type` ∈ {TOUR, PLACE, FOOD}
  - [ ] Nếu `target_type=TOUR`: validate user có booking `status=COMPLETED` cho tour đó
  - [ ] Mặc định `is_approved=false`
  - [ ] Gọi `ActivityService.log(REVIEW_CREATED)`
- [ ] `PUT /api/reviews/{id}` — cập nhật review (chỉ của mình, chưa được duyệt)
- [ ] `DELETE /api/reviews/{id}` — xóa review của mình
- [ ] `GET /api/reviews/me` — list review của user đang đăng nhập

### T13 — Review Public (Guest + User)
- [ ] `GET /api/reviews?targetType=&targetId=` — list reviews `is_approved=true`, pagination
- [ ] `GET /api/places/{slug}/reviews` — reviews của place cụ thể
- [ ] `GET /api/foods/{slug}/reviews` — reviews của food cụ thể
- [ ] `GET /api/tours/{slug}/reviews` — reviews của tour cụ thể

### T14 — Tour Rating (User)
- [ ] Entity `TourRating`
- [ ] `POST /api/tours/{id}/ratings` — rating tour (1–5)
  - [ ] Validate user có booking `status=COMPLETED` cho tour
  - [ ] Upsert (1 user chỉ rating 1 lần / tour)
  - [ ] Trigger DB tự động cập nhật `tours.avg_rating`
- [ ] `GET /api/tours/{id}/ratings/me` — xem rating của mình cho tour

### T15 — Review Likes (User)
- [ ] Entity `ReviewLike`
- [ ] `POST /api/reviews/{id}/like` — like (tạo record, unique constraint)
- [ ] `DELETE /api/reviews/{id}/like` — unlike (xóa record)

### T16 — Comments (User)
- [ ] Entity `Comment` (self-reference `parent_id`)
- [ ] `POST /api/comments` — tạo comment
  - [ ] `target_type` ∈ {REVIEW, NEWS}
  - [ ] `parent_id` nullable (null = top-level, có giá trị = reply)
- [ ] `DELETE /api/comments/{id}` — xóa comment của mình
- [ ] `GET /api/comments?targetType=&targetId=` — list comments (có thể nested)

---

## PHASE 6 — Content (Places, Foods, News)

### T17 — Places & Foods
- [ ] Entity `Place`, `Food`
- [ ] Admin CRUD: `POST/PUT/DELETE /api/admin/places`
- [ ] Admin CRUD: `POST/PUT/DELETE /api/admin/foods`
- [ ] Public: `GET /api/places` — list (filter `is_active=true`)
- [ ] Public: `GET /api/places/{slug}` — chi tiết
- [ ] Public: `GET /api/foods`, `GET /api/foods/{slug}` — tương tự

### T18 — News
- [ ] Entity `News`
- [ ] `POST /api/admin/news` — tạo bài viết (`is_published=false` mặc định)
- [ ] `PUT /api/admin/news/{id}` — cập nhật
- [ ] `DELETE /api/admin/news/{id}` — xóa
- [ ] `PATCH /api/admin/news/{id}/publish` — publish (`is_published=true`, set `published_at`)
- [ ] `GET /api/news` — list bài đã published (Guest + User), pagination
- [ ] `GET /api/news/{slug}` — chi tiết bài viết

---

## PHASE 7 — Admin Management API

### T19 — Admin: Manage Users
- [ ] `GET /api/admin/users` — list users (filter: `role`, `isActive`, search `name/email`, pagination)
- [ ] `GET /api/admin/users/{id}` — chi tiết user (kèm bookings gần đây)
- [ ] `PATCH /api/admin/users/{id}/activate` — kích hoạt tài khoản (`is_active=true`)
- [ ] `PATCH /api/admin/users/{id}/deactivate` — khóa tài khoản (`is_active=false`)

### T20 — Admin: Manage Bookings
- [ ] `GET /api/admin/bookings` — list tất cả bookings (filter: `status`, `fromDate`, `toDate`, `userId`, pagination)
- [ ] `GET /api/admin/bookings/{id}` — chi tiết booking (kèm payment info)
- [ ] `PATCH /api/admin/bookings/{id}/complete` — đánh dấu `COMPLETED`
- [ ] `PATCH /api/admin/bookings/{id}/cancel` — hủy booking bởi admin

### T21 — Admin: Manage Reviews
- [ ] `GET /api/admin/reviews` — list reviews (filter: `isApproved`, `targetType`, pagination)
- [ ] `PATCH /api/admin/reviews/{id}/approve` — duyệt review (`is_approved=true`)
- [ ] `PATCH /api/admin/reviews/{id}/reject` — từ chối / xóa review
- [ ] `DELETE /api/admin/reviews/{id}` — xóa review

### T22 — Admin: Revenue Report
- [ ] `GET /api/admin/revenue` — tổng quan
  - Params: `from`, `to` (date range)
  - Response: tổng doanh thu, số booking theo status, doanh thu theo tháng (group by)
- [ ] `GET /api/admin/revenue/tours` — top tours theo doanh thu trong kỳ

---

## PHASE 8 — Admin UI

> Chọn 1 trong 2 hướng:
> - **Option A**: Thymeleaf (server-side, trong cùng Spring Boot app)
> - **Option B**: SPA riêng (React/Vue) gọi vào Admin API

### T23 — Admin UI Setup
- [ ] Chọn approach (Thymeleaf hoặc SPA)
- [ ] Tích hợp template/layout chung: sidebar, header, breadcrumb
- [ ] Auth guard: redirect về login nếu chưa có JWT
- [ ] Trang Login admin

### T24 — Dashboard
- [ ] Thống kê nhanh: tổng user, tổng tour, booking hôm nay, doanh thu tháng này
- [ ] Chart doanh thu theo tuần/tháng

### T25 — UI: Manage Users
- [ ] Danh sách users (search, filter, pagination)
- [ ] Kích hoạt / Khóa tài khoản
- [ ] Xem chi tiết user

### T26 — UI: Manage Categories & Tours
- [ ] CRUD categories (tree view)
- [ ] CRUD tours (form tạo/sửa tour với upload ảnh)
- [ ] Quản lý schedules của từng tour
- [ ] Đổi status tour

### T27 — UI: Manage Bookings
- [ ] Danh sách bookings (filter status, date)
- [ ] Chi tiết booking kèm thông tin payment
- [ ] Cập nhật status booking

### T28 — UI: Manage Reviews
- [ ] Danh sách reviews chờ duyệt
- [ ] Approve / Reject review

### T29 — UI: Revenue Report
- [ ] Bộ lọc khoảng thời gian
- [ ] Hiển thị tổng doanh thu, bảng theo tháng
- [ ] Top tours doanh thu cao nhất

---

## PHASE 9 — Cross-cutting Concerns

### T30 — Activity Log
- [ ] Entity `Activity`
- [ ] `ActivityService.log(userId, bookingId, type, metadata)` — tái sử dụng ở T10, T11, T12
- [ ] `GET /api/users/me/activities` — user xem lịch sử hoạt động (pagination)
- [ ] `GET /api/admin/activities` — admin xem tất cả (filter `type`, `userId`)

### T31 — Validation & Error Handling
- [ ] Annotation `@Valid` trên tất cả `@RequestBody`
- [ ] Chuẩn hóa error response: `{ status, code, message, errors[] }`
- [ ] Handle: 400 validation, 401 unauthorized, 403 forbidden, 404 not found, 409 conflict, 500 server error

### T32 — Testing
- [ ] Unit test `AuthService` (register, login, refresh token)
- [ ] Unit test `BookingService` (tạo booking, validate slot, cancel)
- [ ] Unit test `PaymentService` (tạo payment, validate)
- [ ] Integration test `AuthController` (MockMvc)
- [ ] Integration test `BookingController` (MockMvc)

---

## Spring Initializr — Dependency Checklist

Khi tạo project tại [start.spring.io](https://start.spring.io), chọn:

| Dependency | Dùng cho |
|---|---|
| Spring Web | REST API |
| Spring Data JPA | ORM / Database |
| Spring Security | Auth & Authorization |
| OAuth2 Client | Facebook, Google, Twitter login |
| PostgreSQL Driver | Kết nối PostgreSQL |
| Lombok | Giảm boilerplate code |
| Validation | `@Valid`, `@NotNull`, ... |
| Flyway Migration | *(optional)* Quản lý schema version |

**Thêm thủ công vào `pom.xml` sau khi tạo project:**
```xml
<!-- JWT -->
<dependency>
    <groupId>io.jsonwebtoken</groupId>
    <artifactId>jjwt-api</artifactId>
    <version>0.12.5</version>
</dependency>
<dependency>
    <groupId>io.jsonwebtoken</groupId>
    <artifactId>jjwt-impl</artifactId>
    <version>0.12.5</version>
    <scope>runtime</scope>
</dependency>
<dependency>
    <groupId>io.jsonwebtoken</groupId>
    <artifactId>jjwt-jackson</artifactId>
    <version>0.12.5</version>
    <scope>runtime</scope>
</dependency>

<!-- MapStruct (DTO mapping) -->
<dependency>
    <groupId>org.mapstruct</groupId>
    <artifactId>mapstruct</artifactId>
    <version>1.5.5.Final</version>
</dependency>
```

---

## Progress Tracker

| Phase | Tasks | Status |
|---|---|---|
| 1 — Foundation | T01 | ⬜ |
| 2 — Auth & User | T02, T03, T04, T05 | ⬜ |
| 3 — Category & Tour | T06, T07, T08, T09 | ⬜ |
| 4 — Booking & Payment | T10, T11 | ⬜ |
| 5 — Social | T12, T13, T14, T15, T16 | ⬜ |
| 6 — Content | T17, T18 | ⬜ |
| 7 — Admin API | T19, T20, T21, T22 | ⬜ |
| 8 — Admin UI | T23–T29 | ⬜ |
| 9 — Cross-cutting | T30, T31, T32 | ⬜ |

> ⬜ Not started · 🔄 In progress · ✅ Done
