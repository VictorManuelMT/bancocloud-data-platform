-- =============================================================================
-- V002__catalogos_seed.sql — Datos semilla de catálogos (corrección #3)
-- Sin estos INSERT, cualquier carga falla por llave foránea. Idempotente:
-- puede correrse varias veces (ON CONFLICT DO NOTHING).
-- Los valores son idénticos a los que emite generar_demo_bancocloud.py.
-- Aplica sobre: master v12 (tablas reference ya existen, vacías salvo monedas).
-- =============================================================================

INSERT INTO reference.monedas (moneda_id, nombre, simbolo) VALUES
('PEN', 'Soles Peruanos', 'S/'),
('USD', 'Dolares Estadounidenses', '$')
ON CONFLICT (moneda_id) DO NOTHING;

INSERT INTO reference.canales (canal_id, codigo_canal, nombre_canal, estado) VALUES
(1, 'APP_MOVIL', 'App Movil Interbank', 'ACTIVO'),
(2, 'WEB', 'Banca por Internet', 'ACTIVO'),
(3, 'AGENCIA', 'Agencia Fisica', 'ACTIVO'),
(4, 'ATM', 'Cajero Automatico', 'ACTIVO'),
(5, 'PLIN', 'Billetera Plin', 'ACTIVO'),
(6, 'POS', 'Terminal POS Comercio', 'ACTIVO'),
(7, 'QR', 'Pago QR Interoperable', 'ACTIVO')
ON CONFLICT (canal_id) DO NOTHING;

-- 10 sucursales: 9 físicas + 1 digital (id 10). Los canales digitales
-- (APP_MOVIL, WEB, PLIN, QR) apuntan a la sucursal DIGITAL.
INSERT INTO reference.sucursales (sucursal_id, codigo_sucursal, nombre_sucursal, departamento, provincia, distrito, tipo_sucursal, estado) VALUES
(1, 'SUC-001', 'Agencia Miraflores', 'Lima', 'Lima', 'Miraflores', 'FISICA', 'ACTIVA'),
(2, 'SUC-002', 'Agencia San Isidro', 'Lima', 'Lima', 'San Isidro', 'FISICA', 'ACTIVA'),
(3, 'SUC-003', 'Agencia Arequipa', 'Arequipa', 'Arequipa', 'Yanahuara', 'FISICA', 'ACTIVA'),
(4, 'SUC-004', 'Agencia Trujillo', 'La Libertad', 'Trujillo', 'Victor Larco', 'FISICA', 'ACTIVA'),
(5, 'SUC-005', 'Agencia Piura', 'Piura', 'Piura', 'Piura', 'FISICA', 'ACTIVA'),
(6, 'SUC-006', 'Agencia Cusco', 'Cusco', 'Cusco', 'Wanchaq', 'FISICA', 'ACTIVA'),
(7, 'SUC-007', 'Agencia Huancayo', 'Junin', 'Huancayo', 'Huancayo', 'FISICA', 'ACTIVA'),
(8, 'SUC-008', 'Agencia Chiclayo', 'Lambayeque', 'Chiclayo', 'Chiclayo', 'FISICA', 'ACTIVA'),
(9, 'SUC-009', 'Agencia Huaraz', 'Ancash', 'Huaraz', 'Huaraz', 'FISICA', 'ACTIVA'),
(10, 'SUC-DIG', 'Canal Digital', 'Lima', 'Lima', 'Miraflores', 'DIGITAL', 'ACTIVA')
ON CONFLICT (sucursal_id) DO NOTHING;

INSERT INTO reference.productos (producto_id, codigo_producto, nombre_producto, familia_producto, moneda_id, tasa_interes_referencial) VALUES
(1, 'CTA_AHORRO_PEN', 'Cuenta Ahorro Soles', 'CUENTA', 'PEN', 1.50),
(2, 'CTA_CTE_PEN', 'Cuenta Corriente Soles', 'CUENTA', 'PEN', 0.50),
(3, 'CTA_SUELDO_PEN', 'Cuenta Sueldo Soles', 'CUENTA', 'PEN', 2.00),
(4, 'CTA_AHORRO_USD', 'Cuenta Ahorro Dolares', 'CUENTA', 'USD', 0.80),
(5, 'CTA_CTE_USD', 'Cuenta Corriente Dolares', 'CUENTA', 'USD', 0.25),
(6, 'CTA_SUELDO_USD', 'Cuenta Sueldo Dolares', 'CUENTA', 'USD', 1.00),
(7, 'TARJ_DEBITO', 'Tarjeta Debito', 'TARJETA', 'PEN', 0.00),
(8, 'TARJ_CREDITO', 'Tarjeta Credito', 'TARJETA', 'PEN', 45.00),
(9, 'CRED_PERSONAL', 'Credito Personal', 'CREDITO', 'PEN', 32.50),
(10, 'CRED_HIPOTECARIO', 'Credito Hipotecario', 'CREDITO', 'PEN', 9.50),
(11, 'CRED_PYME', 'Credito Pyme Negocios', 'CREDITO', 'PEN', 22.00)
ON CONFLICT (producto_id) DO NOTHING;

SELECT setval(pg_get_serial_sequence('reference.canales', 'canal_id'), (SELECT max(canal_id) FROM reference.canales));
SELECT setval(pg_get_serial_sequence('reference.sucursales', 'sucursal_id'), (SELECT max(sucursal_id) FROM reference.sucursales));
SELECT setval(pg_get_serial_sequence('reference.productos', 'producto_id'), (SELECT max(producto_id) FROM reference.productos));
