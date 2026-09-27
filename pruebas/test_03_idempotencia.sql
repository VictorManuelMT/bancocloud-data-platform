-- TEST 03: transferencia repetida con la misma clave (idempotencia real).
-- La segunda llamada NO crea otra operación: devuelve el tx original.
\set ON_ERROR_STOP on
DO $$
DECLARE
    ca UUID; cb UUID; na BIGINT; nb BIGINT; t1 BIGINT; t2 BIGINT;
BEGIN
    INSERT INTO core.clientes (dni_hash, dni_cifrado, nombre, apellido, email_cifrado,
        fecha_nacimiento, departamento, provincia, distrito)
    VALUES ('TEST03-HASH-A', decode('aa', 'hex'), 'Test', 'TresA', decode('bb', 'hex'),
        '1990-01-01', 'Lima', 'Lima', 'Miraflores') RETURNING cliente_id INTO ca;
    INSERT INTO core.clientes (dni_hash, dni_cifrado, nombre, apellido, email_cifrado,
        fecha_nacimiento, departamento, provincia, distrito)
    VALUES ('TEST03-HASH-B', decode('cc', 'hex'), 'Test', 'TresB', decode('dd', 'hex'),
        '1990-01-01', 'Lima', 'Lima', 'Miraflores') RETURNING cliente_id INTO cb;
    INSERT INTO core.cuentas (cliente_id, producto_id, numero_cuenta, moneda_id,
        saldo_actual, saldo_disponible, saldo_inicial)
    VALUES (ca, 1, 'T03-00000001', 'PEN', 10000.00, 10000.00, 10000.00) RETURNING cuenta_id INTO na;
    INSERT INTO core.cuentas (cliente_id, producto_id, numero_cuenta, moneda_id,
        saldo_actual, saldo_disponible, saldo_inicial)
    VALUES (cb, 1, 'T03-00000002', 'PEN', 10000.00, 10000.00, 10000.00) RETURNING cuenta_id INTO nb;

    t1 := core.sp_transferir_dinero(na, nb, 250.00, 1, 10, 'TEST-03-KEY', 'PEN');
    t2 := core.sp_transferir_dinero(na, nb, 250.00, 1, 10, 'TEST-03-KEY', 'PEN');

    IF t1 <> t2 THEN
        RAISE EXCEPTION 'TEST 03 FAILED: replay devolvio % en vez de %', t2, t1;
    END IF;
    IF (SELECT count(*) FROM core.transacciones WHERE idempotency_key = 'TEST-03-KEY') <> 1 THEN
        RAISE EXCEPTION 'TEST 03 FAILED: se duplico la operacion';
    END IF;
    IF (SELECT saldo_actual FROM core.cuentas WHERE cuenta_id = na) <> 9750.00 THEN
        RAISE EXCEPTION 'TEST 03 FAILED: el dinero se movio dos veces';
    END IF;

    DELETE FROM core.movimientos_contables WHERE transaccion_id = t1;
    DELETE FROM core.idempotencia WHERE canal_id = 1 AND idempotency_key = 'TEST-03-KEY';
    DELETE FROM core.transacciones WHERE transaccion_id = t1;
    DELETE FROM core.cuentas WHERE cuenta_id IN (na, nb);
    DELETE FROM core.clientes WHERE cliente_id IN (ca, cb);
    RAISE NOTICE 'TEST 03 PASSED: replay devuelve la original % sin duplicar', t1;
END; $$;
