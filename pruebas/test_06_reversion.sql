-- TEST 06: reversión compensatoria (el original queda, aparece la inversa).
-- En banca no se borra: se compensa. La tabla core.reversiones enlaza ambas.
\set ON_ERROR_STOP on
DO $$
DECLARE
    ca UUID; cb UUID; na BIGINT; nb BIGINT; t1 BIGINT; t2 BIGINT;
    m0a NUMERIC; m0b NUMERIC;
BEGIN
    INSERT INTO core.clientes (dni_hash, dni_cifrado, nombre, apellido, email_cifrado,
        fecha_nacimiento, departamento, provincia, distrito)
    VALUES ('TEST06-HASH-A', decode('aa', 'hex'), 'Test', 'SeisA', decode('bb', 'hex'),
        '1990-01-01', 'Lima', 'Lima', 'Miraflores') RETURNING cliente_id INTO ca;
    INSERT INTO core.clientes (dni_hash, dni_cifrado, nombre, apellido, email_cifrado,
        fecha_nacimiento, departamento, provincia, distrito)
    VALUES ('TEST06-HASH-B', decode('cc', 'hex'), 'Test', 'SeisB', decode('dd', 'hex'),
        '1990-01-01', 'Lima', 'Lima', 'Miraflores') RETURNING cliente_id INTO cb;
    INSERT INTO core.cuentas (cliente_id, producto_id, numero_cuenta, moneda_id,
        saldo_actual, saldo_disponible, saldo_inicial)
    VALUES (ca, 1, 'T06-00000001', 'PEN', 5000.00, 5000.00, 5000.00) RETURNING cuenta_id INTO na;
    INSERT INTO core.cuentas (cliente_id, producto_id, numero_cuenta, moneda_id,
        saldo_actual, saldo_disponible, saldo_inicial)
    VALUES (cb, 1, 'T06-00000002', 'PEN', 5000.00, 5000.00, 5000.00) RETURNING cuenta_id INTO nb;

    t1 := core.sp_transferir_dinero(na, nb, 500.00, 1, 10, 'TEST-06-KEY-1', 'PEN');
    SELECT saldo_actual INTO m0a FROM core.cuentas WHERE cuenta_id = na;

    -- Reversión: operación inversa (nb -> na) + fila en core.reversiones.
    t2 := core.sp_transferir_dinero(nb, na, 500.00, 1, 10, 'TEST-06-KEY-2', 'PEN');
    INSERT INTO core.reversiones (transaccion_original_id, transaccion_reversion_id,
        motivo, usuario_solicitante)
    VALUES (t1, t2, 'Reversión demo: cargo duplicado', 'test_06');

    IF (SELECT estado FROM core.transacciones WHERE transaccion_id = t1) <> 'COMPLETADA' THEN
        RAISE EXCEPTION 'TEST 06 FAILED: la original % fue alterada', t1;
    END IF;
    IF (SELECT saldo_actual FROM core.cuentas WHERE cuenta_id = na) <> 5000.00 THEN
        RAISE EXCEPTION 'TEST 06 FAILED: efecto neto distinto de cero';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM core.reversiones
                   WHERE transaccion_original_id = t1 AND transaccion_reversion_id = t2) THEN
        RAISE EXCEPTION 'TEST 06 FAILED: falta el enlace de reversion';
    END IF;

    DELETE FROM core.movimientos_contables WHERE transaccion_id IN (t1, t2);
    DELETE FROM core.idempotencia WHERE idempotency_key IN ('TEST-06-KEY-1', 'TEST-06-KEY-2');
    DELETE FROM core.reversiones WHERE transaccion_original_id = t1;
    DELETE FROM core.transacciones WHERE transaccion_id IN (t1, t2);
    DELETE FROM core.cuentas WHERE cuenta_id IN (na, nb);
    DELETE FROM core.clientes WHERE cliente_id IN (ca, cb);
    RAISE NOTICE 'TEST 06 PASSED: original % intacta + compensatoria % (neto 0)', t1, t2;
END; $$;
