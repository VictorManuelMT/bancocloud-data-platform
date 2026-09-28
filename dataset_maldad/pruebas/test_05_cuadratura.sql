-- TEST 05: cuadratura global (débitos = créditos) + saldos desde el ledger.
-- Es la prueba del diferenciador del diseño: toda la base concilia.
\set ON_ERROR_STOP on
DO $$
DECLARE
    v_deb NUMERIC; v_cre NUMERIC; v_mal_tx BIGINT; v_mal_cta BIGINT;
BEGIN
    SELECT coalesce(sum(monto), 0), 0 INTO v_deb, v_cre
    FROM core.movimientos_contables WHERE tipo_movimiento = 'DEBITO';
    SELECT coalesce(sum(monto), 0) INTO v_cre
    FROM core.movimientos_contables WHERE tipo_movimiento = 'CREDITO';
    IF v_deb <> v_cre THEN
        RAISE EXCEPTION 'TEST 05 FAILED: debitos % <> creditos %', v_deb, v_cre;
    END IF;

    SELECT count(*) INTO v_mal_tx FROM (
        SELECT transaccion_id
        FROM core.movimientos_contables
        GROUP BY transaccion_id
        HAVING sum(CASE WHEN tipo_movimiento = 'DEBITO' THEN monto ELSE -monto END) <> 0
    ) s;
    IF v_mal_tx > 0 THEN
        RAISE EXCEPTION 'TEST 05 FAILED: % transacciones descuadradas', v_mal_tx;
    END IF;

    SELECT count(*) INTO v_mal_cta FROM (
        SELECT c.cuenta_id
        FROM core.cuentas c
        LEFT JOIN (
            SELECT cuenta_id,
                   sum(CASE WHEN tipo_movimiento = 'CREDITO' THEN monto ELSE -monto END) AS neto
            FROM core.movimientos_contables GROUP BY cuenta_id
        ) m USING (cuenta_id)
        WHERE round(c.saldo_actual - (c.saldo_inicial + coalesce(m.neto, 0)), 2) <> 0
    ) s;
    IF v_mal_cta > 0 THEN
        RAISE EXCEPTION 'TEST 05 FAILED: % cuentas no salen del ledger', v_mal_cta;
    END IF;

    RAISE NOTICE 'TEST 05 PASSED: D=C=% y 0 cuentas fuera del ledger', v_deb;
END; $$;
