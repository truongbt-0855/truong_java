-- ============================================================
-- TOUR BOOKING SYSTEM — DATABASE SCHEMA v3
-- Database: PostgreSQL 15+
-- ============================================================

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. USER & AUTH
-- ============================================================

CREATE TABLE users (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    full_name     VARCHAR(255)        NOT NULL,
    email         VARCHAR(255)        NOT NULL UNIQUE,
    phone         VARCHAR(20),
    password_hash VARCHAR(255),
    avatar_url    VARCHAR(500),
    role          VARCHAR(20)         NOT NULL DEFAULT 'USER' CHECK (role IN ('ADMIN', 'USER')),
    is_active     BOOLEAN             NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMP           NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMP           NOT NULL DEFAULT NOW(),
    deleted_at    TIMESTAMP
);

CREATE TABLE oauth_accounts (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id          UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider         VARCHAR(20)  NOT NULL CHECK (provider IN ('FACEBOOK', 'TWITTER', 'GOOGLE')),
    provider_user_id VARCHAR(255) NOT NULL,
    access_token     TEXT,
    refresh_token    TEXT,
    token_expires_at TIMESTAMP,
    created_at       TIMESTAMP    NOT NULL DEFAULT NOW(),
    UNIQUE (provider, provider_user_id)
);

CREATE TABLE user_bank_accounts (
    id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id        UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    bank_name      VARCHAR(100) NOT NULL,
    account_number VARCHAR(50)  NOT NULL,
    account_holder VARCHAR(255) NOT NULL,
    is_default     BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at     TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 2. TOUR & CATEGORY
-- ============================================================

CREATE TABLE categories (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parent_id   UUID REFERENCES categories(id) ON DELETE SET NULL,
    name        VARCHAR(255) NOT NULL,
    slug        VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    image_url   VARCHAR(500),
    is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE TABLE tours (
    id                 UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category_id        UUID           REFERENCES categories(id) ON DELETE SET NULL,
    title              VARCHAR(500)   NOT NULL,
    slug               VARCHAR(500)   NOT NULL UNIQUE,
    description        TEXT,
    thumbnail_url      VARCHAR(500),
    base_price         NUMERIC(15, 2) NOT NULL,
    duration_days      INTEGER        NOT NULL CHECK (duration_days > 0),
    max_participants   INTEGER        NOT NULL CHECK (max_participants > 0),
    departure_location VARCHAR(500),
    status             VARCHAR(20)    NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'ACTIVE', 'INACTIVE')),
    avg_rating         NUMERIC(3, 2)  DEFAULT 0 CHECK (avg_rating >= 0 AND avg_rating <= 5),
    created_at         TIMESTAMP      NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMP      NOT NULL DEFAULT NOW(),
    deleted_at         TIMESTAMP
);

CREATE TABLE tour_images (
    id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tour_id    UUID         NOT NULL REFERENCES tours(id) ON DELETE CASCADE,
    image_url  VARCHAR(500) NOT NULL,
    sort_order INTEGER      NOT NULL DEFAULT 0
);

CREATE TABLE tour_schedules (
    id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tour_id        UUID           NOT NULL REFERENCES tours(id) ON DELETE CASCADE,
    departure_date DATE           NOT NULL,
    return_date    DATE           NOT NULL,
    total_slots    INTEGER        NOT NULL CHECK (total_slots > 0),
    price_override NUMERIC(15, 2),           -- NULL = dùng base_price của tour
    status         VARCHAR(20)    NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'FULL', 'CANCELLED')),
    CHECK (return_date >= departure_date)
);

-- ============================================================
-- 3. CONTENT (target cho polymorphic reviews)
-- ============================================================

CREATE TABLE places (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name          VARCHAR(255) NOT NULL,
    slug          VARCHAR(255) NOT NULL UNIQUE,
    location      VARCHAR(500),
    description   TEXT,
    thumbnail_url VARCHAR(500),
    is_active     BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE TABLE foods (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name          VARCHAR(255) NOT NULL,
    slug          VARCHAR(255) NOT NULL UNIQUE,
    location      VARCHAR(500),
    description   TEXT,
    thumbnail_url VARCHAR(500),
    is_active     BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE TABLE news (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    author_id     UUID         NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    title         VARCHAR(500) NOT NULL,
    slug          VARCHAR(500) NOT NULL UNIQUE,
    content       TEXT,
    thumbnail_url VARCHAR(500),
    is_published  BOOLEAN      NOT NULL DEFAULT FALSE,
    published_at  TIMESTAMP,
    created_at    TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- Junction tables: tour <-> places, tour <-> foods
CREATE TABLE tour_places (
    tour_id  UUID NOT NULL REFERENCES tours(id) ON DELETE CASCADE,
    place_id UUID NOT NULL REFERENCES places(id) ON DELETE CASCADE,
    PRIMARY KEY (tour_id, place_id)
);

CREATE TABLE tour_foods (
    tour_id UUID NOT NULL REFERENCES tours(id) ON DELETE CASCADE,
    food_id UUID NOT NULL REFERENCES foods(id) ON DELETE CASCADE,
    PRIMARY KEY (tour_id, food_id)
);

-- ============================================================
-- 4. BOOKING & PAYMENT
-- ============================================================

CREATE TABLE bookings (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id          UUID           NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    schedule_id      UUID           NOT NULL REFERENCES tour_schedules(id) ON DELETE RESTRICT,
    booking_code     VARCHAR(50)    NOT NULL UNIQUE,
    num_participants INTEGER        NOT NULL CHECK (num_participants > 0),
    total_amount     NUMERIC(15, 2) NOT NULL,
    status           VARCHAR(20)    NOT NULL DEFAULT 'PENDING'
                         CHECK (status IN ('PENDING', 'CONFIRMED', 'CANCELLED', 'COMPLETED')),
    booked_at        TIMESTAMP      NOT NULL DEFAULT NOW(),
    cancelled_at     TIMESTAMP,
    cancel_reason    TEXT
);

CREATE TABLE payments (
    id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    booking_id        UUID           NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
    bank_account_id   UUID           REFERENCES user_bank_accounts(id) ON DELETE SET NULL,
    amount            NUMERIC(15, 2) NOT NULL,
    currency          VARCHAR(10)    NOT NULL DEFAULT 'VND',
    method            VARCHAR(30)    NOT NULL CHECK (method IN ('INTERNET_BANKING', 'WALLET', 'CREDIT_CARD')),
    status            VARCHAR(20)    NOT NULL DEFAULT 'PENDING'
                          CHECK (status IN ('PENDING', 'SUCCESS', 'FAILED', 'REFUNDED')),
    transaction_ref   VARCHAR(255),
    gateway_response  TEXT,
    paid_at           TIMESTAMP
);

-- ============================================================
-- 5. REVIEW & SOCIAL
-- ============================================================

CREATE TABLE reviews (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_type VARCHAR(10) NOT NULL CHECK (target_type IN ('TOUR', 'PLACE', 'FOOD')),
    target_id   UUID        NOT NULL,
    booking_id  UUID        REFERENCES bookings(id) ON DELETE SET NULL,
    title       VARCHAR(500),
    content     TEXT,
    rating      SMALLINT    CHECK (rating BETWEEN 1 AND 5),
    is_approved BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMP   NOT NULL DEFAULT NOW(),
    -- Mỗi user chỉ review 1 lần cho mỗi target
    UNIQUE (user_id, target_type, target_id)
);

CREATE TABLE review_likes (
    id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id    UUID      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    review_id  UUID      NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, review_id)   -- chống like 2 lần
);

CREATE TABLE comments (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_type VARCHAR(10) NOT NULL CHECK (target_type IN ('REVIEW', 'NEWS')),
    target_id   UUID        NOT NULL,
    parent_id   UUID        REFERENCES comments(id) ON DELETE CASCADE,  -- self-ref, NULL = top-level
    content     TEXT        NOT NULL,
    created_at  TIMESTAMP   NOT NULL DEFAULT NOW()
);

CREATE TABLE tour_ratings (
    id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id    UUID      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tour_id    UUID      NOT NULL REFERENCES tours(id) ON DELETE CASCADE,
    booking_id UUID      NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
    score      SMALLINT  NOT NULL CHECK (score BETWEEN 1 AND 5),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, tour_id)   -- mỗi user chỉ rating 1 lần / tour
);

-- ============================================================
-- 6. ACTIVITY LOG
-- ============================================================

CREATE TABLE activities (
    id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    booking_id UUID        REFERENCES bookings(id) ON DELETE SET NULL,
    type       VARCHAR(30) NOT NULL CHECK (type IN (
                   'BOOKING_CREATED',
                   'BOOKING_CANCELLED',
                   'PAYMENT_COMPLETED',
                   'REVIEW_CREATED',
                   'TOUR_COMPLETED'
               )),
    metadata   JSONB,
    created_at TIMESTAMP   NOT NULL DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================

-- users
CREATE INDEX idx_users_email      ON users(email) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_role       ON users(role);

-- tours
CREATE INDEX idx_tours_status     ON tours(status) WHERE deleted_at IS NULL;
CREATE INDEX idx_tours_category   ON tours(category_id);
CREATE INDEX idx_tours_slug       ON tours(slug);

-- tour_schedules
CREATE INDEX idx_schedules_tour        ON tour_schedules(tour_id);
CREATE INDEX idx_schedules_departure   ON tour_schedules(departure_date);
CREATE INDEX idx_schedules_status      ON tour_schedules(status);

-- bookings
CREATE INDEX idx_bookings_user         ON bookings(user_id);
CREATE INDEX idx_bookings_schedule     ON bookings(schedule_id);
CREATE INDEX idx_bookings_status       ON bookings(status);
CREATE INDEX idx_bookings_code         ON bookings(booking_code);

-- payments
CREATE INDEX idx_payments_booking      ON payments(booking_id);
CREATE INDEX idx_payments_status       ON payments(status);

-- reviews
CREATE INDEX idx_reviews_user          ON reviews(user_id);
CREATE INDEX idx_reviews_target        ON reviews(target_type, target_id);
CREATE INDEX idx_reviews_approved      ON reviews(is_approved);

-- comments
CREATE INDEX idx_comments_target       ON comments(target_type, target_id);
CREATE INDEX idx_comments_parent       ON comments(parent_id);

-- tour_ratings
CREATE INDEX idx_ratings_tour          ON tour_ratings(tour_id);

-- activities
CREATE INDEX idx_activities_user       ON activities(user_id);
CREATE INDEX idx_activities_type       ON activities(type);
CREATE INDEX idx_activities_booking    ON activities(booking_id);

-- ============================================================
-- TRIGGER: tự động update tours.avg_rating sau mỗi insert/delete rating
-- ============================================================

CREATE OR REPLACE FUNCTION update_tour_avg_rating()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE tours
    SET avg_rating = (
        SELECT COALESCE(AVG(score), 0)
        FROM tour_ratings
        WHERE tour_id = COALESCE(NEW.tour_id, OLD.tour_id)
    ),
    updated_at = NOW()
    WHERE id = COALESCE(NEW.tour_id, OLD.tour_id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_avg_rating
AFTER INSERT OR UPDATE OR DELETE ON tour_ratings
FOR EACH ROW EXECUTE FUNCTION update_tour_avg_rating();

-- ============================================================
-- TRIGGER: tự động update tours.updated_at
-- ============================================================

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_tours_updated_at
BEFORE UPDATE ON tours
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
