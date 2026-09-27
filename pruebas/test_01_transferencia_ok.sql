-- TEST 01: transferencia correcta (saldos + ledger cuadran).
-- Uso: psql -d <bd> -v ON_ERROR_STOP=1 -f pruebas/test_01_transferencia_ok.sql
\set ON_ERROR_STOP on
DO $$
DECLARE
    ca UUID; cb UUID; na BIGINT; nb BIGINT; tx BIGINT;
    sa NUMERIC; sb NUMERIC;
BEGIN
    INSERT INTO core.clientes (dni_hash, dni_cifrado, nombre, apellido, email_cifrado,
        fecha_nacimiento, departamento, provincia, distrito)
    VALUES ('TEST01-HASH-A', decode('aa', 'hex'), 'Test', 'UnoA', decode('bb', 'hex'),
        '1990-01-01', 'Lima', 'Lima', 'Miraflores') RETURNING cliente_id INTO ca;
    INSERT INTO core.clientes (dni_hash, dni_cifrado, nombre, apellido, email_cifrado,
        fecha_nacimiento, departamento, provincia, distrito)
    VALUES ('TEST01-HASH-B', decode('cc', 'hex'), 'Test', 'UnoB', decode('dd', 'hex'),
        '1990-01-01', 'Lima', 'Lima', 'Miraflores') RETURNING cliente_id INTO cb;
    INSERT INTO core.cuentas (cliente_id, producto_id, numero_cuenta, moneda_id,
        saldo_actual, saldo_disponible, saldo_inicial)
    VALUES (ca, 1, 'T01-00000001', 'PEN', 10000.00, 10000.00, 10000.00) RETURNING cuenta_id INTO na;
    INSERT INTO core.cuentas (cliente_id, producto_id, numero_cuenta, moneda_id,
        saldo_actual, saldo_disponible, saldo_inicial)
    VALUES (cb, 1, 'T01-00000002', 'PEN', 10000.00, 10000.00, 10000.00) RETURNING cuenta_id INTO nb;

    tx := core.sp_transferir_dinero(na, nb, 100.00, 1, 10, 'TEST-01-KEY', 'PEN');

    SELECT saldo_actual INTO sa FROM core.cuentas WHERE cuenta_id = na;
    SELECT saldo_actual INTO sb FROM core.cuentas WHERE cuenta_id = nb;
    IF sa <> 9900.00 OR sb <> 10100.00 THEN
        RAISE EXCEPTION 'TEST 01 FAILED: saldos % / % (esperado 9900 / 10100)', sa, sb;
    END IF;
    IF (SELECT count(*) FROM core.movimientos_contables WHERE transaccion_id = tx) <> 2 THEN
        RAISE EXCEPTION 'TEST 01 FAILED: la tx % no tiene 2 asientos', tx;
    END IF;
    IF (SELECT sum(CASE WHEN tipo_movimiento = 'DEBITO' THEN monto ELSE -monto END)
        FROM core.movimientos_contables WHERE transaccion_id = tx) <> 0 THEN
        RAISE EXCEPTION 'TEST 01 FAILED: descuadre en tx %', tx;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM core.idempotencia WHERE canal_id = 1 AND idempotency_key = 'TEST-01-KEY') THEN
        RAISE EXCEPTION 'TEST 01 FAILED: falta fila en core.idempotencia';
    END IF;

    DELETE FROM core.movimientos_contables WHERE transaccion_id = tx;
    DELETE FROM core.idempotencia WHERE canal_id = 1 AND idempotency_key = 'TEST-01-KEY';
    DELETE FROM core.transacciones WHERE transaccion_id = tx;
    DELETE FROM core.cuentas WHERE cuenta_id IN (na, nb);
    DELETE FROM core.clientes WHERE cliente_id IN (ca, cb);
    RAISE NOTICE 'TEST 01 PASSED: transferencia %, saldos 9900/10100, ledger 1D+1C', tx;
END; $$;
