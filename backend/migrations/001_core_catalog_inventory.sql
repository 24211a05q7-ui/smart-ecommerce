-- Migration 001: core catalog and inventory
-- Part 1: shared trigger function and users

-- Automatically refreshes updated_at whenever a row is updated.
CREATE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE users (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name          TEXT NOT NULL CHECK (length(btrim(name)) > 0),
  email         TEXT NOT NULL CHECK (length(btrim(email)) > 0),
  password_hash TEXT NOT NULL,
  role          TEXT NOT NULL DEFAULT 'customer' CHECK (role IN ('customer', 'admin')),
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Emails are unique ignoring case: A@x.com and a@x.com are the same account.
CREATE UNIQUE INDEX users_email_lower_key ON users (lower(email));

CREATE TRIGGER users_set_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- Part 2: categories, products, product images

CREATE TABLE categories (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name       TEXT NOT NULL CHECK (length(btrim(name)) > 0),
  slug       TEXT NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  parent_id  BIGINT REFERENCES categories (id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (parent_id IS NULL OR parent_id <> id)
);

CREATE INDEX categories_parent_id_idx ON categories (parent_id);

CREATE TRIGGER categories_set_updated_at
  BEFORE UPDATE ON categories
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE products (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  category_id BIGINT NOT NULL REFERENCES categories (id) ON DELETE RESTRICT,
  name        TEXT NOT NULL CHECK (length(btrim(name)) > 0),
  slug        TEXT NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  description TEXT NOT NULL DEFAULT '',
  price       NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
  sku         TEXT NOT NULL CHECK (length(btrim(sku)) > 0),
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- SKUs are unique ignoring case: PH-001 and ph-001 are the same product code.
CREATE UNIQUE INDEX products_sku_lower_key ON products (lower(sku));

-- PostgreSQL does NOT index foreign keys automatically.
-- Without this, "all products in a category" would scan the whole table.
CREATE INDEX products_category_id_idx ON products (category_id);

CREATE TRIGGER products_set_updated_at
  BEFORE UPDATE ON products
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE product_images (
  id                   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id           BIGINT NOT NULL REFERENCES products (id) ON DELETE CASCADE,
  url                  TEXT NOT NULL CHECK (length(btrim(url)) > 0),
  cloudinary_public_id TEXT,
  sort_order           INTEGER NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX product_images_product_sort_idx ON product_images (product_id, sort_order);


-- Part 3: inventory and inventory movements

CREATE TABLE inventory (
  product_id        BIGINT PRIMARY KEY REFERENCES products (id) ON DELETE CASCADE,
  stock_quantity    INTEGER NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
  reserved_quantity INTEGER NOT NULL DEFAULT 0 CHECK (reserved_quantity >= 0),
  reorder_level     INTEGER NOT NULL DEFAULT 0 CHECK (reorder_level >= 0),
  lead_time_days    INTEGER NOT NULL DEFAULT 7 CHECK (lead_time_days >= 0),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT inventory_reserved_within_stock CHECK (reserved_quantity <= stock_quantity)
);

CREATE TRIGGER inventory_set_updated_at
  BEFORE UPDATE ON inventory
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Ledger of PHYSICAL stock changes only. Reservations never appear here;
-- they are tracked by inventory_reservations (Phase 5).
CREATE TABLE inventory_movements (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id     BIGINT NOT NULL REFERENCES products (id) ON DELETE RESTRICT,
  change_qty     INTEGER NOT NULL,
  stock_after    INTEGER NOT NULL CHECK (stock_after >= 0),
  reason         TEXT NOT NULL,
  reference_type TEXT,
  reference_id   BIGINT,
  note           TEXT,
  created_by     BIGINT REFERENCES users (id) ON DELETE RESTRICT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT movements_change_nonzero CHECK (change_qty <> 0),
  CONSTRAINT movements_reason_valid CHECK (reason IN ('restock', 'sale', 'adjustment', 'return')),
  CONSTRAINT movements_reason_sign CHECK (
    (reason = 'sale' AND change_qty < 0)
    OR (reason IN ('restock', 'return') AND change_qty > 0)
    OR reason = 'adjustment'
  ),
  CONSTRAINT movements_reference_pair CHECK ((reference_type IS NULL) = (reference_id IS NULL)),
  CONSTRAINT movements_reference_type_valid CHECK (reference_type IS NULL OR reference_type IN ('order')),
  CONSTRAINT movements_sale_needs_order CHECK (reason <> 'sale' OR reference_type IS NOT NULL),
  CONSTRAINT movements_admin_reasons_need_actor CHECK (
    reason NOT IN ('restock', 'adjustment') OR created_by IS NOT NULL
  )
);

CREATE INDEX inventory_movements_product_created_idx
  ON inventory_movements (product_id, created_at);

-- The ledger is append-only: history can be added to, never rewritten.
CREATE FUNCTION prevent_ledger_change() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION '% on % is not allowed: the table is append-only', TG_OP, TG_TABLE_NAME;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER inventory_movements_append_only
  BEFORE UPDATE OR DELETE ON inventory_movements
  FOR EACH ROW EXECUTE FUNCTION prevent_ledger_change();