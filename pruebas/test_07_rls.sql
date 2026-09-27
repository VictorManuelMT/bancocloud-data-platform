-- TEST 07: RLS (el cliente A no ve ni toca lo del cliente B).
-- Cubre el hallazgo: WITH CHECK en INSERT/UPDATE + política en clientes.
-- Se ejecuta como superuser pero baja a ROLE app_test con SET ROLE.
\set ON_ERROR_STOP on
DO $$
DECLARE
    ca UUID; cb UUID; na BIGINT; nb BIGINT; v_seen BIGINT; v_cli BIGINT;
BEGIN
    INSERT INTO core.clientes (dni_hash, dni_cifrado, nombre, apellido, email_cifrado,
        fecha_nacimiento, departamento, provincia, distrito)
    VALUES ('TEST07-HASH-A', decode('aa', 'hex'), 'Test', 'SieteA', decode('bb', 'hex'),
        '1990-01-01', 'Lima', 'Lima', 'Miraflores') RETURNING cliente_id INTO ca;
    INSERT INTO core.clientes (dni_hash, dni_cifrado, nombre, apellido, email_cifrado,
        fecha_nacimiento, departamento, provincia, distrito)
    VALUES ('TEST07-HASH-B', decode('cc', 'hex'), 'Test', 'SieteB', decode('dd', 'hex'),
        '1990-01-01', 'Lima', 'Lima', 'Miraflores') RETURNING cliente_id INTO cb;
    INSERT INTO core.cuentas (cliente_id, producto_id, numero_cuenta, moneda_id,
        saldo_actual, saldo_disponible, saldo_inicial)
    VALUES (ca, 1, 'T07-00000001', 'PEN', 1000.00, 1000.00, 1000.00) RETURNING cuenta_id INTO na;
    INSERT INTO core.cuentas (cliente_id, producto_id, numero_cuenta, moneda_id,
        saldo_actual, saldo_disponible, saldo_inicial)
    VALUES (cb, 1, 'T07-00000002', 'PEN', 1000.00, 1000.00, 1000.00) RETURNING cuenta_id INTO nb;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_test') THEN
        CREATE ROLE app_test NOLOGIN;
    END IF;
    GRANT USAGE ON SCHEMA core TO app_test;
    GRANT SELECT, INSERT, UPDATE ON core.clientes, core.cuentas, core.transacciones TO app_test;
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA core TO app_test;

    PERFORM set_config('app.current_client_id', ca::TEXT, false);
    SET ROLE app_test;

    SELECT count(*) INTO v_seen FROM core.cuentas;
    IF v_seen <> 1 THEN
        RESET ROLE;
        RAISE EXCEPTION 'TEST 07 FAILED: A ve % cuentas (esperaba 1)', v_seen;
    END IF;
    SELECT count(*) INTO v_cli FROM core.clientes;
    IF v_cli <> 1 THEN
        RESET ROLE;
        RAISE EXCEPTION 'TEST 07 FAILED: A ve % clientes (esperaba 1)', v_cli;
    END IF;
    BEGIN
        INSERT INTO core.transacciones (cuenta_origen_id, canal_id, sucursal_id,
            tipo_transaccion, monto, moneda_id, idempotency_key)
        VALUES (nb, 1, 10, 'RETIRO', 10.00, 'PEN', 'TEST-07-EVIL');
        RESET ROLE;
        RAISE EXCEPTION 'TEST 07 FAILED: A pudo insertar sobre la cuenta de B';
    EXCEPTION WHEN insufficient_privilege THEN
        -- Esperado: WITH CHECK bloquea. Nada que hacer.
    END;
    RESET ROLE;

    DELETE FROM core.cuentas WHERE cuenta_id IN (na, nb);
    DELETE FROM core.clientes WHERE cliente_id IN (ca, cb);
    DROP OWNED BY app_test;
    DROP ROLE app_test;
    RAISE NOTICE 'TEST 07 PASSED: A ve solo lo suyo e INSERT ajeno bloqueado';
END; $$;
