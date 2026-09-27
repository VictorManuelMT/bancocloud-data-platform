-- TEST 04: 100 transferencias concurrentes contra la misma cuenta (dblink).
-- Si hubiera actualizaciones perdidas, el saldo final no cuadraría al céntimo.
-- Requiere la extensión dblink (incluida en PostgreSQL contrib).
\set ON_ERROR_STOP on
CREATE EXTENSION IF NOT EXISTS dblink;
DO $$
DECLARE
    cb UUID; nt BIGINT; i INT; espera INT;
    conn TEXT := 'dbname=' || current_database();
    ca UUID; na BIGINT;
BEGIN
    INSERT INTO core.clientes (dni_hash, dni_cifrado, nombre, apellido, email_cifrado,
        fecha_nacimiento, departamento, provincia, distrito)
    VALUES ('TEST04-HASH-T', decode('aa', 'hex'), 'Test', 'CuatroT', decode('bb', 'hex'),
        '1990-01-01', 'Lima', 'Lima', 'Miraflores') RETURNING cliente_id INTO cb;
    INSERT INTO core.cuentas (cliente_id, producto_id, numero_cuenta, moneda_id,
        saldo_actual, saldo_disponible, saldo_inicial)
    VALUES (cb, 1, 'T04-TARGET', 'PEN', 0.00, 0.00, 0.00) RETURNING cuenta_id INTO nt;
    FOR i IN 1..100 LOOP
        INSERT INTO core.clientes (dni_hash, dni_cifrado, nombre, apellido, email_cifrado,
            fecha_nacimiento, departamento, provincia, distrito)
        VALUES ('TEST04-HASH-' || i, decode('cc', 'hex'), 'Test', 'Cuatro' || i, decode('dd', 'hex'),
            '1990-01-01', 'Lima', 'Lima', 'Miraflores') RETURNING cliente_id INTO ca;
        INSERT INTO core.cuentas (cliente_id, producto_id, numero_cuenta, moneda_id,
            saldo_actual, saldo_disponible, saldo_inicial)
        VALUES (ca, 1, 'T04-SRC-' || i, 'PEN', 1000.00, 1000.00, 1000.00) RETURNING cuenta_id INTO na;
        PERFORM dblink_connect('t04_' || i, conn);
        PERFORM dblink_send_query('t04_' || i,
            format('SELECT core.sp_transferir_dinero(%s, %s, 10.00, 1, 10, %L, %L)',
                   na, nt, 'TEST-04-KEY-' || i, 'PEN'));
    END LOOP;
    -- Esperar a que terminen las 100 (máx ~30 s).
    espera := 0;
    LOOP
        EXIT WHEN NOT EXISTS (
            SELECT 1 FROM generate_series(1, 100) i
            WHERE dblink_is_busy('t04_' || i) = 1);
        PERFORM pg_sleep(0.1);
        espera := espera + 1;
        IF espera > 300 THEN
            RAISE EXCEPTION 'TEST 04 FAILED: timeout esperando workers';
        END IF;
    END LOOP;
    FOR i IN 1..100 LOOP
        PERFORM dblink_get_result('t04_' || i);
        PERFORM dblink_disconnect('t04_' || i);
    END LOOP;

    IF (SELECT saldo_actual FROM core.cuentas WHERE cuenta_id = nt) <> 1000.00 THEN
        RAISE EXCEPTION 'TEST 04 FAILED: saldo destino % (esperado 1000.00)',
            (SELECT saldo_actual FROM core.cuentas WHERE cuenta_id = nt);
    END IF;
    IF (SELECT count(*) FROM core.transacciones WHERE idempotency_key LIKE 'TEST-04-KEY-%') <> 100 THEN
        RAISE EXCEPTION 'TEST 04 FAILED: no hay 100 transacciones';
    END IF;
    IF (SELECT sum(CASE WHEN tipo_movimiento = 'DEBITO' THEN monto ELSE -monto END)
        FROM core.movimientos_contables m JOIN core.transacciones t USING (transaccion_id)
        WHERE t.idempotency_key LIKE 'TEST-04-KEY-%') <> 0 THEN
        RAISE EXCEPTION 'TEST 04 FAILED: descuadre en el ledger concurrente';
    END IF;

    DELETE FROM core.movimientos_contables WHERE transaccion_id IN
        (SELECT transaccion_id FROM core.transacciones WHERE idempotency_key LIKE 'TEST-04-KEY-%');
    DELETE FROM core.idempotencia WHERE idempotency_key LIKE 'TEST-04-KEY-%';
    DELETE FROM core.transacciones WHERE idempotency_key LIKE 'TEST-04-KEY-%';
    DELETE FROM core.cuentas WHERE numero_cuenta LIKE 'T04-%';
    DELETE FROM core.clientes WHERE dni_hash LIKE 'TEST04-HASH-%';
    RAISE NOTICE 'TEST 04 PASSED: 100/100 concurrentes, destino en 1000.00 exactos';
END; $$;
