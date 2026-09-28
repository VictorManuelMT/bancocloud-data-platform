-- DEMO DNI (versión 1/2): CON la clave autorizada SÍ se recupera.
-- Dura segundos: búsqueda O(1) por dni_hash (HMAC) + descifrado PGP del dni_cifrado.
-- Uso: psql -d <bd> -v ON_ERROR_STOP=1 -f pruebas/demo_dni_autorizado.sql
\set ON_ERROR_STOP on
DO $$
DECLARE
    v_dni TEXT := '87654321';
    v_hash TEXT := encode(hmac('87654321', 'demo-key-2026', 'sha256'), 'hex');
    v_claro TEXT;
BEGIN
    -- Fila demo con el patrón real: hash para buscar, PGP para recuperar.
    INSERT INTO core.clientes (dni_hash, dni_cifrado, nombre, apellido, email_cifrado,
        fecha_nacimiento, departamento, provincia, distrito)
    VALUES (v_hash, pgp_sym_encrypt(v_dni, 'demo-key-2026'),
        'Demo', 'Autorizada', pgp_sym_encrypt('demo@ibk.pe', 'demo-key-2026'),
        '1990-05-05', 'Lima', 'Lima', 'Miraflores');

    -- 1) Localizo por hash sin descifrar nada (rápido, O(1)).
    -- 2) Recupero el DNI con la clave de sesión autorizada.
    SELECT pgp_sym_decrypt(dni_cifrado, current_setting('app.dni_key', true))
    INTO v_claro FROM core.clientes WHERE dni_hash = v_hash;

    IF v_claro <> v_dni THEN
        RAISE EXCEPTION 'DEMO FAILED: recupero % en vez de %', v_claro, v_dni;
    END IF;
    DELETE FROM core.clientes WHERE dni_hash = v_hash;
    RAISE NOTICE 'DEMO OK (autorizada): hash localiza en O(1) y la clave recupera el DNI %', v_claro;
END; $$;
