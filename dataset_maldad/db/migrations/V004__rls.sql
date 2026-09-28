-- =============================================================================
-- V004__rls.sql — Row Level Security completo (hallazgo de la revisión)
-- Problemas que corrige:
-- 1) Las políticas solo cubrían SELECT con USING: un cliente podía INSERTAR
--    filas sobre cuentas ajenas. Ahora INSERT y UPDATE exigen WITH CHECK.
-- 2) core.clientes tenía RLS activado SIN ninguna política: la tabla quedaba
--    bloqueada entera. Ahora el cliente ve su propia fila.
-- El contexto lo fija la app con: SET app.current_client_id = '<uuid>';
-- (superuser y owner bypassean RLS; las pruebas usan SET ROLE app_test).
-- =============================================================================

DROP POLICY IF EXISTS policy_cuentas_cliente ON core.cuentas;
DROP POLICY IF EXISTS policy_transacciones_cliente ON core.transacciones;

-- core.clientes: cada cliente ve su propia fila.
CREATE POLICY policy_clientes_propios ON core.clientes
    FOR SELECT
    USING (cliente_id = NULLIF(current_setting('app.current_client_id', true), '')::UUID);

-- core.cuentas: ver, crear y modificar solo cuentas propias.
CREATE POLICY policy_cuentas_select ON core.cuentas
    FOR SELECT
    USING (cliente_id = NULLIF(current_setting('app.current_client_id', true), '')::UUID);

CREATE POLICY policy_cuentas_insert ON core.cuentas
    FOR INSERT
    WITH CHECK (cliente_id = NULLIF(current_setting('app.current_client_id', true), '')::UUID);

CREATE POLICY policy_cuentas_update ON core.cuentas
    FOR UPDATE
    USING (cliente_id = NULLIF(current_setting('app.current_client_id', true), '')::UUID)
    WITH CHECK (cliente_id = NULLIF(current_setting('app.current_client_id', true), '')::UUID);

-- core.transacciones: operar solo sobre cuentas de origen propias.
CREATE POLICY policy_transacciones_select ON core.transacciones
    FOR SELECT
    USING (
        cuenta_origen_id IN (
            SELECT cuenta_id FROM core.cuentas
            WHERE cliente_id = NULLIF(current_setting('app.current_client_id', true), '')::UUID
        )
    );

CREATE POLICY policy_transacciones_insert ON core.transacciones
    FOR INSERT
    WITH CHECK (
        cuenta_origen_id IN (
            SELECT cuenta_id FROM core.cuentas
            WHERE cliente_id = NULLIF(current_setting('app.current_client_id', true), '')::UUID
        )
    );

CREATE POLICY policy_transacciones_update ON core.transacciones
    FOR UPDATE
    USING (
        cuenta_origen_id IN (
            SELECT cuenta_id FROM core.cuentas
            WHERE cliente_id = NULLIF(current_setting('app.current_client_id', true), '')::UUID
        )
    )
    WITH CHECK (
        cuenta_origen_id IN (
            SELECT cuenta_id FROM core.cuentas
            WHERE cliente_id = NULLIF(current_setting('app.current_client_id', true), '')::UUID
        )
    );
