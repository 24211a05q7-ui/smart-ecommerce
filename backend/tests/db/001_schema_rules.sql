-- Checks every rule in migration 001 (users, catalog, inventory, ledger).
-- Run only against a TEST database:
--   psql -U postgres -d smart_commerce_test -f tests/db/001_schema_rules.sql
-- Everything happens inside a transaction that is rolled back at the end.

BEGIN;

CREATE TEMP TABLE results (
  id     INTEGER GENERATED ALWAYS AS IDENTITY,
  label  TEXT,
  passed BOOLEAN,
  detail TEXT
);

-- Runs a statement that MUST fail, and checks it failed for the expected reason
-- (a constraint name, or text in the error message).
CREATE FUNCTION pg_temp.expect_fail(p_label TEXT, p_stmt TEXT, p_expected TEXT) RETURNS VOID AS $$
DECLARE
  v_constraint TEXT;
  v_message    TEXT;
BEGIN
  EXECUTE p_stmt;
  INSERT INTO pg_temp.results (label, passed, detail)
  VALUES (p_label, FALSE, 'statement succeeded but should have failed');
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME, v_message = MESSAGE_TEXT;
  IF v_constraint = p_expected OR v_message LIKE '%' || p_expected || '%' THEN
    INSERT INTO pg_temp.results (label, passed, detail) VALUES (p_label, TRUE, p_expected);
  ELSE
    INSERT INTO pg_temp.results (label, passed, detail)
    VALUES (p_label, FALSE,
            format('expected %s, got constraint=%s message=%s', p_expected, COALESCE(v_constraint, '-'), v_message));
  END IF;
END;
$$ LANGUAGE plpgsql;

DO $do$
DECLARE
  u BIGINT; c BIGINT; p BIGINT; v_sum BIGINT; v_stock INTEGER;
BEGIN
  -- Fixtures
  INSERT INTO users (name, email, password_hash, role)
    VALUES ('Check Admin', 'check-admin@example.test', 'x', 'admin') RETURNING id INTO u;
  INSERT INTO categories (name, slug) VALUES ('Check', 'check-category') RETURNING id INTO c;
  INSERT INTO products (category_id, name, slug, price, sku)
    VALUES (c, 'Check Product', 'check-product', 10.00, 'CHK-001') RETURNING id INTO p;
  INSERT INTO inventory (product_id, reorder_level, lead_time_days) VALUES (p, 5, 10);

  -- Legitimate lifecycle: opening stock, reserve 4, confirm the sale, reserve 2 more
  UPDATE inventory SET stock_quantity = stock_quantity + 10 WHERE product_id = p;
  INSERT INTO inventory_movements (product_id, change_qty, stock_after, reason, created_by, note)
    VALUES (p, 10, 10, 'restock', u, 'Opening stock');
  UPDATE inventory SET reserved_quantity = reserved_quantity + 4 WHERE product_id = p;
  UPDATE inventory SET stock_quantity = stock_quantity - 4, reserved_quantity = reserved_quantity - 4
    WHERE product_id = p;
  INSERT INTO inventory_movements (product_id, change_qty, stock_after, reason, reference_type, reference_id)
    VALUES (p, -4, 6, 'sale', 'order', 1001);
  UPDATE inventory SET reserved_quantity = 2 WHERE product_id = p;

  -- Users
  PERFORM pg_temp.expect_fail('users: duplicate email in different case',
    $q$INSERT INTO users (name, email, password_hash) VALUES ('Dup', 'CHECK-ADMIN@EXAMPLE.TEST', 'x')$q$,
    'users_email_lower_key');
  PERFORM pg_temp.expect_fail('users: invalid role',
    $q$INSERT INTO users (name, email, password_hash, role) VALUES ('R', 'r@example.test', 'x', 'superuser')$q$,
    'users_role_check');
  PERFORM pg_temp.expect_fail('users: blank name',
    $q$INSERT INTO users (name, email, password_hash) VALUES ('   ', 'b@example.test', 'x')$q$,
    'users_name_check');

  -- Catalog
  PERFORM pg_temp.expect_fail('products: negative price',
    format($q$INSERT INTO products (category_id, name, slug, price, sku) VALUES (%s, 'Neg', 'neg-price', -5, 'CHK-002')$q$, c),
    'products_price_check');
  PERFORM pg_temp.expect_fail('products: duplicate slug',
    format($q$INSERT INTO products (category_id, name, slug, price, sku) VALUES (%s, 'Dup', 'check-product', 10, 'CHK-003')$q$, c),
    'products_slug_key');
  PERFORM pg_temp.expect_fail('products: duplicate SKU in different case',
    format($q$INSERT INTO products (category_id, name, slug, price, sku) VALUES (%s, 'Dup', 'dup-sku', 10, 'chk-001')$q$, c),
    'products_sku_lower_key');
  PERFORM pg_temp.expect_fail('products: invalid slug format',
    format($q$INSERT INTO products (category_id, name, slug, price, sku) VALUES (%s, 'Bad', 'Bad Slug!', 10, 'CHK-004')$q$, c),
    'products_slug_check');
  PERFORM pg_temp.expect_fail('products: category must exist',
    $q$INSERT INTO products (category_id, name, slug, price, sku) VALUES (0, 'Orphan', 'orphan', 10, 'CHK-005')$q$,
    'products_category_id_fkey');
  PERFORM pg_temp.expect_fail('categories: cannot be its own parent',
    format('UPDATE categories SET parent_id = id WHERE id = %s', c),
    'categories_check');
  PERFORM pg_temp.expect_fail('categories: cannot delete one that has products',
    format('DELETE FROM categories WHERE id = %s', c),
    'products_category_id_fkey');

  -- Inventory
  PERFORM pg_temp.expect_fail('inventory: stock cannot be negative',
    format('UPDATE inventory SET stock_quantity = -1 WHERE product_id = %s', p),
    'inventory_reserved_within_stock');
  PERFORM pg_temp.expect_fail('inventory: cannot reserve more than stock',
    format('UPDATE inventory SET reserved_quantity = 7 WHERE product_id = %s', p),
    'inventory_reserved_within_stock');
  PERFORM pg_temp.expect_fail('inventory: cannot lower stock below reserved',
    format('UPDATE inventory SET stock_quantity = 1 WHERE product_id = %s', p),
    'inventory_reserved_within_stock');

  -- Ledger
  PERFORM pg_temp.expect_fail('ledger: zero change',
    format($q$INSERT INTO inventory_movements (product_id, change_qty, stock_after, reason, created_by) VALUES (%s, 0, 6, 'adjustment', %s)$q$, p, u),
    'movements_change_nonzero');
  PERFORM pg_temp.expect_fail('ledger: a sale must be negative',
    format($q$INSERT INTO inventory_movements (product_id, change_qty, stock_after, reason, reference_type, reference_id) VALUES (%s, 3, 9, 'sale', 'order', 1002)$q$, p),
    'movements_reason_sign');
  PERFORM pg_temp.expect_fail('ledger: a sale needs an order reference',
    format($q$INSERT INTO inventory_movements (product_id, change_qty, stock_after, reason) VALUES (%s, -1, 5, 'sale')$q$, p),
    'movements_sale_needs_order');
  PERFORM pg_temp.expect_fail('ledger: a restock needs the admin who did it',
    format($q$INSERT INTO inventory_movements (product_id, change_qty, stock_after, reason) VALUES (%s, 5, 11, 'restock')$q$, p),
    'movements_admin_reasons_need_actor');
  PERFORM pg_temp.expect_fail('ledger: reference type without an id',
    format($q$INSERT INTO inventory_movements (product_id, change_qty, stock_after, reason, reference_type) VALUES (%s, 1, 7, 'return', 'order')$q$, p),
    'movements_reference_pair');
  PERFORM pg_temp.expect_fail('ledger: history cannot be edited',
    format($q$UPDATE inventory_movements SET note = 'tampered' WHERE product_id = %s$q$, p),
    'append-only');
  PERFORM pg_temp.expect_fail('ledger: history cannot be deleted',
    format('DELETE FROM inventory_movements WHERE product_id = %s', p),
    'append-only');
  PERFORM pg_temp.expect_fail('products: cannot hard-delete one with stock history',
    format('DELETE FROM products WHERE id = %s', p),
    'inventory_movements_product_id_fkey');

  -- Reconciliation: the ledger must add up to the stock level
  SELECT COALESCE(SUM(change_qty), 0) INTO v_sum FROM inventory_movements WHERE product_id = p;
  SELECT stock_quantity INTO v_stock FROM inventory WHERE product_id = p;
  INSERT INTO pg_temp.results (label, passed, detail)
    VALUES ('ledger total equals stock_quantity', v_sum = v_stock, format('ledger=%s stock=%s', v_sum, v_stock));
END
$do$;

SELECT passed, label, detail FROM pg_temp.results ORDER BY id;
SELECT count(*) FILTER (WHERE passed) AS passed, count(*) FILTER (WHERE NOT passed) AS failed FROM pg_temp.results;

ROLLBACK;