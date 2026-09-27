-- TEST 02: transferencia sin saldo (falla atómica, no deja nada a medias).
\set ON_ERROR_STOP on
DO $$
DECLARE
    ca UUID; cb UUID; na BIGINT; nb BIGINT; ntx0 BIGINT; nmv0 BIGINT;
BEGIN
    INSERT INTO core.clientes (dni_hash, dni_cifrado, nombre, apellido, email_cifrado,
        fecha_nacimiento, departamento, provincia, distrito)
    VALUES ('TEST02-HASH-A', decode('aa', 'hex'), 'Test', 'DosA', decode('bb', 'hex'),
        '1990-01-01', 'Lima', 'Lima', 'Miraflores') RETURNING cliente_id INTO ca;
    INSERT INTO core.clientes (dni_hash, dni_cifrado, nombre, apellido, email_cifrado,
        fecha_nacimiento, departamento, provincia, distrito)
    VALUES ('TEST02-HASH-B', decode('cc', 'hex'), 'Test', 'DosB', decode('dd', 'hex'),
        '1990-01-01', 'Lima', 'Lima', 'Miraflores') RETURNING cliente_id INTO cb;
    INSERT INTO core.cuentas (cliente_id, producto_id, numero_cuenta, moneda_id,
        saldo_actual, saldo_disponible, saldo_inicial)
    VALUES (ca, 1, 'T02-00000001', 'PEN', 50.00, 50.00, 50.00) RETURNING cuenta_id INTO na;
    INSERT INTO core.cuentas (cliente_id, producto_id, numero_cuenta, moneda_id,
        saldo_actual, saldo_disponible, saldo_inicial)
    VALUES (cb, 1, 'T02-00000002', 'PEN', 50.00, 50.00, 50.00) RETURNING cuenta_id INTO nb;
    SELECT count(*) INTO ntx0 FROM core.transacciones WHERE idempotency_key = 'TEST-02-KEY';
    SELECT count(*) INTO nmv0 FROM core.movimientos_contables m
        JOIN core.transacciones t USING (transaccion_id) WHERE t.idempotency_key = 'TEST-02-KEY';

    BEGIN
        PERFORM core.sp_transferir_dinero(na, nb, 20000.00, 1, 10, 'TEST-02-KEY', 'PEN');
        RAISE EXCEPTION 'TEST 02 FAILED: la transferencia sin saldo no fallo';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%SALDO_INSUFICIENTE%' THEN
            RAISE EXCEPTION 'TEST 02 FAILED: error inesperado: %', SQLERRM;
        END IF;
    END;

    IF (SELECT count(*) FROM core.transacciones WHERE idempotency_key = 'TEST-02-KEY') <> ntx0 THEN
        RAISE EXCEPTION 'TEST 02 FAILED: quedo una transaccion a medias';
    END IF;
    IF (SELECT count(*) FROM core.movimientos_contables m
        JOIN core.transacciones t USING (transaccion_id)
        WHERE t.idempotency_key = 'TEST-02-KEY') <> nmv0 THEN
        RAISE EXCEPTION 'TEST 02 FAILED: quedaron asientos a medias';
    END IF;
    IF (SELECT saldo_actual FROM core.cuentas WHERE cuenta_id = na) <> 50.00 THEN
        RAISE EXCEPTION 'TEST 02 FAILED: el saldo origen cambio';
    END IF;

    DELETE FROM core.cuentas WHERE cuenta_id IN (na, nb);
    DELETE FROM core.clientes WHERE cliente_id IN (ca, cb);
    RAISE NOTICE 'TEST 02 PASSED: SALDO_INSUFICIENTE y cero filas a medias';
END; $$;
