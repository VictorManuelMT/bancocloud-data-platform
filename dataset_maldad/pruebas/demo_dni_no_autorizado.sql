-- DEMO DNI (versión 2/2): SIN la clave YA NO se puede recuperar.
-- Misma fila, clave equivocada: pgcrypto falla y el DNI no sale.
-- Uso: psql -d <bd> -v ON_ERROR_STOP=1 -f pruebas/demo_dni_no_autorizado.sql
\set ON_ERROR_STOP on
DO $$
DECLARE
    v_hash TEXT := encode(hmac('87654321', 'demo-key-2026', 'sha256'), 'hex');
BEGIN
    INSERT INTO core.clientes (dni_hash, dni_cifrado, nombre, apellido, email_cifrado,
        fecha_nacimiento, departamento, provincia, distrito)
    VALUES (v_hash, pgp_sym_encrypt('87654321', 'demo-key-2026'),
        'Demo', 'Bloqueada', pgp_sym_encrypt('demo@ibk.pe', 'demo-key-2026'),
        '1990-05-05', 'Lima', 'Lima', 'Miraflores');

    BEGIN
        PERFORM pgp_sym_decrypt(dni_cifrado, current_setting('app.dni_key', true))
        FROM core.clientes WHERE dni_hash = v_hash;
        DELETE FROM core.clientes WHERE dni_hash = v_hash;
        RAISE EXCEPTION 'DEMO FAILED: sin clave válida igual se leyó el DNI';
    EXCEPTION WHEN OTHERS THEN
        DELETE FROM core.clientes WHERE dni_hash = v_hash;
        RAISE NOTICE 'DEMO OK (no autorizada): sin la clave no se recupera (%)', SQLERRM;
    END;
END; $$;
