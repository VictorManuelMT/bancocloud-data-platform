-- =============================================================================
-- BANCOCLOUD INTERBANK DIGITAL ANDINO - MASTER SQL COMPLETE v13.0 ENTERPRISE
-- =============================================================================
-- Basado estrictamente en arquitectura-bd-interbank-potenciado-v12.docx
-- Incluye: 6 Esquemas, Catálogos, OLTP 16 Tablas, Ledger Contable, AI/RAG (pgvector),
-- DataOps (Circuit Breaker), DW Star Schema, RLS, Indexes, Procedures, Triggers & Views.
-- v13: tabla core.idempotencia (PK canal+clave), catalogos completos, columnas de
-- negocio (segmento/comision/saldo_inicial/disponible tarjeta), RLS completo,
-- 12 particiones mensuales oct-2025/sep-2026. Ver db/migrations/ (V001-V005).
-- Mismo estado final que migrar desde v12: sp_transferir_dinero chequea la clave
-- de idempotencia ANTES de validar saldo (correccion 7.8.6).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. ACTIVACIÓN DE EXTENSIONES Y ESQUEMAS TEMÁTICOS
-- -----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";

CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS reference;
CREATE SCHEMA IF NOT EXISTS security;
CREATE SCHEMA IF NOT EXISTS dq;
CREATE SCHEMA IF NOT EXISTS ai;
CREATE SCHEMA IF NOT EXISTS analytics;

-- -----------------------------------------------------------------------------
-- 1. ESQUEMA REFERENCE (CATÁLOGOS MAESTROS DESACOPLADOS)
-- -----------------------------------------------------------------------------
CREATE TABLE reference.monedas (
    moneda_id VARCHAR(3) PRIMARY KEY, -- 'PEN', 'USD'
    nombre VARCHAR(50) NOT NULL,
    simbolo VARCHAR(5) NOT NULL
);

INSERT INTO reference.monedas (moneda_id, nombre, simbolo) VALUES
('PEN', 'Soles Peruanos', 'S/'),
('USD', 'Dólares Estadounidenses', '$')
ON CONFLICT (moneda_id) DO NOTHING;

CREATE TABLE reference.sucursales (
    sucursal_id SERIAL PRIMARY KEY,
    codigo_sucursal VARCHAR(10) UNIQUE NOT NULL,
    nombre_sucursal VARCHAR(100) NOT NULL,
    departamento VARCHAR(50) NOT NULL,
    provincia VARCHAR(50) NOT NULL,
    distrito VARCHAR(50) NOT NULL,
    tipo_sucursal VARCHAR(20) DEFAULT 'FISICA' CHECK (tipo_sucursal IN ('FISICA', 'DIGITAL', 'AGENTE')),
    estado VARCHAR(20) DEFAULT 'ACTIVA' CHECK (estado IN ('ACTIVA', 'INACTIVA'))
);

CREATE TABLE reference.canales (
    canal_id SERIAL PRIMARY KEY,
    codigo_canal VARCHAR(20) UNIQUE NOT NULL, -- APP_MOVIL, WEB, AGENCIA, ATM, PLIN, POS, QR
    nombre_canal VARCHAR(50) NOT NULL,
    estado VARCHAR(20) DEFAULT 'ACTIVO' CHECK (estado IN ('ACTIVO', 'MANTENIMIENTO'))
);

CREATE TABLE reference.productos (
    producto_id SERIAL PRIMARY KEY,
    codigo_producto VARCHAR(20) UNIQUE NOT NULL,
    nombre_producto VARCHAR(100) NOT NULL,
    familia_producto VARCHAR(30) NOT NULL CHECK (familia_producto IN ('CUENTA', 'TARJETA', 'CREDITO')),
    moneda_id VARCHAR(3) NOT NULL REFERENCES reference.monedas(moneda_id),
    tasa_interes_referencial NUMERIC(5,2) DEFAULT 0.00
);

CREATE TABLE reference.tipos_transaccion (
    codigo VARCHAR(30) PRIMARY KEY,
    descripcion TEXT NOT NULL,
    requiere_destino BOOLEAN NOT NULL -- solo transferencias llevan destino
);

-- -----------------------------------------------------------------------------
-- 2. ESQUEMA CORE (TABLAS OPERACIONALES BANCARIAS)
-- -----------------------------------------------------------------------------
CREATE TABLE core.clientes (
    cliente_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    dni_hash VARCHAR(64) UNIQUE NOT NULL, -- HMAC-SHA256 con Pepper de KMS para búsqueda O(1)
    dni_cifrado BYTEA NOT NULL,           -- pgcrypto PGP Sym para desencriptación autorizada
    nombre VARCHAR(100) NOT NULL,
    apellido VARCHAR(100) NOT NULL,
    email_cifrado BYTEA NOT NULL,
    telefono_cifrado BYTEA,
    fecha_nacimiento DATE NOT NULL,
    departamento VARCHAR(50) NOT NULL,
    provincia VARCHAR(50) NOT NULL,
    distrito VARCHAR(50) NOT NULL,
    segmento_cliente VARCHAR(20) NOT NULL DEFAULT 'MASIVO' CHECK (segmento_cliente IN ('MASIVO', 'PREFERENTE', 'PATRIMONIAL')),
    nivel_riesgo VARCHAR(20) DEFAULT 'BAJO' CHECK (nivel_riesgo IN ('BAJO', 'MEDIO', 'ALTO', 'CRITICO')),
    score_riesgo INT CHECK (score_riesgo BETWEEN 300 AND 850),
    estado VARCHAR(20) DEFAULT 'ACTIVO' CHECK (estado IN ('ACTIVO', 'BLOQUEADO', 'BAJA')),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE core.cuentas (
    cuenta_id BIGSERIAL PRIMARY KEY,
    cliente_id UUID NOT NULL REFERENCES core.clientes(cliente_id),
    producto_id INT NOT NULL REFERENCES reference.productos(producto_id),
    numero_cuenta VARCHAR(20) UNIQUE NOT NULL,
    moneda_id VARCHAR(3) NOT NULL REFERENCES reference.monedas(moneda_id),
    saldo_actual NUMERIC(15,2) DEFAULT 0.00 NOT NULL,
    saldo_disponible NUMERIC(15,2) DEFAULT 0.00 NOT NULL,
    saldo_inicial NUMERIC(15,2) DEFAULT 0.00 NOT NULL,
    estado VARCHAR(20) DEFAULT 'ACTIVA' CHECK (estado IN ('ACTIVA', 'CONGELADA', 'CERRADA')),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE core.tarjetas (
    tarjeta_id BIGSERIAL PRIMARY KEY,
    cuenta_id BIGINT REFERENCES core.cuentas(cuenta_id), -- NULL para Tarjetas de Crédito puras
    cliente_id UUID NOT NULL REFERENCES core.clientes(cliente_id),
    token_tarjeta_hash VARCHAR(64) UNIQUE NOT NULL,     -- HMAC-SHA256 tokenizado PCI-DSS
    mascara_pan VARCHAR(19) NOT NULL,                    -- Ej: 4578-XXXX-XXXX-1234
    tipo_tarjeta VARCHAR(10) CHECK (tipo_tarjeta IN ('DEBITO', 'CREDITO')),
    limite_credito NUMERIC(15,2) DEFAULT 0.00,
    saldo_utilizado NUMERIC(15,2) DEFAULT 0.00,
    saldo_disponible NUMERIC(15,2) DEFAULT 0.00 NOT NULL,
    fecha_corte INT CHECK (fecha_corte BETWEEN 1 AND 31),
    fecha_pago INT CHECK (fecha_pago BETWEEN 1 AND 31),
    estado VARCHAR(20) DEFAULT 'ACTIVA' CHECK (estado IN ('ACTIVA', 'BLOQUEADA_ROBO', 'EXPIRADA')),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- MÓDULO DE CRÉDITOS DESACOPLADO
CREATE TABLE core.solicitudes_credito (
    solicitud_id BIGSERIAL PRIMARY KEY,
    cliente_id UUID NOT NULL REFERENCES core.clientes(cliente_id),
    producto_id INT NOT NULL REFERENCES reference.productos(producto_id),
    monto_solicitado NUMERIC(15,2) NOT NULL CHECK (monto_solicitado > 0),
    plazo_meses INT NOT NULL,
    fecha_solicitud TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    estado VARCHAR(20) DEFAULT 'EVALUACION' CHECK (estado IN ('EVALUACION', 'APROBADO', 'RECHAZADO'))
);

CREATE TABLE core.evaluaciones_credito (
    evaluacion_id BIGSERIAL PRIMARY KEY,
    solicitud_id BIGINT NOT NULL REFERENCES core.solicitudes_credito(solicitud_id),
    score_calculado INT NOT NULL,
    capacidad_pago NUMERIC(15,2) NOT NULL,
    decision VARCHAR(20) NOT NULL CHECK (decision IN ('APROBADO', 'RECHAZADO')),
    sustento TEXT NOT NULL,
    fecha_evaluacion TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE core.creditos (
    credito_id BIGSERIAL PRIMARY KEY,
    solicitud_id BIGINT UNIQUE NOT NULL REFERENCES core.solicitudes_credito(solicitud_id),
    cliente_id UUID NOT NULL REFERENCES core.clientes(cliente_id),
    producto_id INT NOT NULL REFERENCES reference.productos(producto_id),
    monto_aprobado NUMERIC(15,2) NOT NULL,
    saldo_capital_pendiente NUMERIC(15,2) NOT NULL,
    tasa_tea NUMERIC(5,2) NOT NULL,
    plazo_meses INT NOT NULL,
    dias_mora INT DEFAULT 0 CHECK (dias_mora >= 0),
    bucket_riesgo VARCHAR(20) DEFAULT 'AL_DIA' CHECK (bucket_riesgo IN ('AL_DIA', '1_30_DIAS', '31_60_DIAS', '61_90_DIAS', '90_MAS_DIAS')),
    estado VARCHAR(20) DEFAULT 'VIGENTE' CHECK (estado IN ('VIGENTE', 'EN_MORA', 'CANCELADO', 'CASTIGADO'))
);

CREATE TABLE core.cuotas (
    cuota_id BIGSERIAL PRIMARY KEY,
    credito_id BIGINT NOT NULL REFERENCES core.creditos(credito_id),
    numero_cuota INT NOT NULL,
    monto_capital NUMERIC(15,2) NOT NULL,
    monto_interes NUMERIC(15,2) NOT NULL,
    seguro_desgravamen NUMERIC(15,2) DEFAULT 0.00,
    monto_total_cuota NUMERIC(15,2) NOT NULL,
    fecha_vencimiento DATE NOT NULL,
    estado VARCHAR(20) DEFAULT 'PENDIENTE' CHECK (estado IN ('PENDIENTE', 'PAGADO', 'VENCIDO'))
);

CREATE TABLE core.pagos_credito (
    pago_id BIGSERIAL PRIMARY KEY,
    cuota_id BIGINT NOT NULL REFERENCES core.cuotas(cuota_id),
    monto_pagado NUMERIC(15,2) NOT NULL CHECK (monto_pagado > 0),
    fecha_pago TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    canal_id INT NOT NULL REFERENCES reference.canales(canal_id)
);

-- TRANSACCIONES Y LEDGER CONTABLE
CREATE TABLE core.transacciones (
    transaccion_id BIGSERIAL,
    cuenta_origen_id BIGINT NOT NULL REFERENCES core.cuentas(cuenta_id),
    cuenta_destino_id BIGINT REFERENCES core.cuentas(cuenta_id),
    canal_id INT NOT NULL REFERENCES reference.canales(canal_id),
    sucursal_id INT NOT NULL REFERENCES reference.sucursales(sucursal_id),
    tipo_transaccion VARCHAR(30) NOT NULL,
    monto NUMERIC(15,2) NOT NULL CHECK (monto > 0.00),
    moneda_id VARCHAR(3) NOT NULL REFERENCES reference.monedas(moneda_id),
    idempotency_key VARCHAR(64) NOT NULL,
    comision NUMERIC(15,2) DEFAULT 0.00 NOT NULL,
    run_id UUID,
    fecha_transaccion TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    estado VARCHAR(20) DEFAULT 'COMPLETADA' CHECK (estado IN ('COMPLETADA', 'RECHAZADA', 'REVERTIDA')),
    CONSTRAINT fk_transacciones_tipo_transaccion FOREIGN KEY (tipo_transaccion) REFERENCES reference.tipos_transaccion(codigo),
    PRIMARY KEY (transaccion_id, fecha_transaccion)
) PARTITION BY RANGE (fecha_transaccion);

-- PARTICIONES MENSUALES DE LA VENTANA DEMO (12 meses)
CREATE TABLE core.transacciones_y2025m10 PARTITION OF core.transacciones
    FOR VALUES FROM ('2025-10-01 00:00:00+00') TO ('2025-11-01 00:00:00+00');
CREATE TABLE core.transacciones_y2025m11 PARTITION OF core.transacciones
    FOR VALUES FROM ('2025-11-01 00:00:00+00') TO ('2025-12-01 00:00:00+00');
CREATE TABLE core.transacciones_y2025m12 PARTITION OF core.transacciones
    FOR VALUES FROM ('2025-12-01 00:00:00+00') TO ('2026-01-01 00:00:00+00');
CREATE TABLE core.transacciones_y2026m01 PARTITION OF core.transacciones
    FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2026-02-01 00:00:00+00');
CREATE TABLE core.transacciones_y2026m02 PARTITION OF core.transacciones
    FOR VALUES FROM ('2026-02-01 00:00:00+00') TO ('2026-03-01 00:00:00+00');
CREATE TABLE core.transacciones_y2026m03 PARTITION OF core.transacciones
    FOR VALUES FROM ('2026-03-01 00:00:00+00') TO ('2026-04-01 00:00:00+00');
CREATE TABLE core.transacciones_y2026m04 PARTITION OF core.transacciones
    FOR VALUES FROM ('2026-04-01 00:00:00+00') TO ('2026-05-01 00:00:00+00');
CREATE TABLE core.transacciones_y2026m05 PARTITION OF core.transacciones
    FOR VALUES FROM ('2026-05-01 00:00:00+00') TO ('2026-06-01 00:00:00+00');
CREATE TABLE core.transacciones_y2026m06 PARTITION OF core.transacciones
    FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');
CREATE TABLE core.transacciones_y2026m07 PARTITION OF core.transacciones
    FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');
CREATE TABLE core.transacciones_y2026m08 PARTITION OF core.transacciones
    FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');
CREATE TABLE core.transacciones_y2026m09 PARTITION OF core.transacciones
    FOR VALUES FROM ('2026-09-01 00:00:00+00') TO ('2026-10-01 00:00:00+00');

CREATE TABLE core.idempotencia (
    canal_id         INT NOT NULL REFERENCES reference.canales(canal_id),
    idempotency_key  VARCHAR(64) NOT NULL,
    transaccion_id   BIGINT NOT NULL,
    fecha_transaccion TIMESTAMPTZ NOT NULL,
    creado_en        TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (canal_id, idempotency_key)
);

CREATE TABLE core.movimientos_contables (
    movimiento_id BIGSERIAL PRIMARY KEY,
    transaccion_id BIGINT NOT NULL,
    cuenta_id BIGINT NOT NULL REFERENCES core.cuentas(cuenta_id),
    tipo_movimiento VARCHAR(7) NOT NULL CHECK (tipo_movimiento IN ('DEBITO', 'CREDITO')),
    monto NUMERIC(15,2) NOT NULL CHECK (monto > 0.00),
    fecha_movimiento TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE core.reversiones (
    reversion_id BIGSERIAL PRIMARY KEY,
    transaccion_original_id BIGINT NOT NULL,
    transaccion_reversion_id BIGINT NOT NULL,
    motivo TEXT NOT NULL,
    usuario_solicitante VARCHAR(50) NOT NULL,
    fecha_ejecucion TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- -----------------------------------------------------------------------------
-- 3. ESQUEMA SECURITY (AUDITORÍA Y SEGURIDAD FORENSE)
-- -----------------------------------------------------------------------------
CREATE TABLE security.audit_logs (
    audit_id BIGSERIAL PRIMARY KEY,
    tabla_afectada VARCHAR(50) NOT NULL,
    operacion VARCHAR(10) NOT NULL, -- INSERT, UPDATE, DELETE
    usuario_db VARCHAR(50) NOT NULL,
    old_data JSONB,                 -- Fotografía del estado anterior
    new_data JSONB,                 -- Fotografía del estado posterior
    fecha_evento TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- PROTECCIÓN DE INMUTABILIDAD ESTRICTA ANTE AUDITORÍA SBS
REVOKE UPDATE, DELETE, TRUNCATE ON security.audit_logs FROM PUBLIC;

-- TRIGGER FUNCTION PARA CAPTURA FORENSE DE DELTAS EN JSONB
CREATE OR REPLACE FUNCTION security.fn_audit_forense_jsonb() RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        INSERT INTO security.audit_logs (tabla_afectada, operacion, usuario_db, old_data, new_data)
        VALUES (TG_TABLE_NAME, 'DELETE', CURRENT_USER, to_jsonb(OLD), NULL);
        RETURN OLD;
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO security.audit_logs (tabla_afectada, operacion, usuario_db, old_data, new_data)
        VALUES (TG_TABLE_NAME, 'UPDATE', CURRENT_USER, to_jsonb(OLD), to_jsonb(NEW));
        RETURN NEW;
    ELSIF (TG_OP = 'INSERT') THEN
        INSERT INTO security.audit_logs (tabla_afectada, operacion, usuario_db, old_data, new_data)
        VALUES (TG_TABLE_NAME, 'INSERT', CURRENT_USER, NULL, to_jsonb(NEW));
        RETURN NEW;
    END IF;
    RETURN NULL;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_transacciones_forense 
AFTER INSERT OR UPDATE OR DELETE ON core.transacciones 
FOR EACH ROW EXECUTE FUNCTION security.fn_audit_forense_jsonb();

-- -----------------------------------------------------------------------------
-- 4. ESQUEMA DQ (DATA QUALITY & DATAOPS CIRCUIT BREAKER)
-- -----------------------------------------------------------------------------
CREATE TABLE dq.data_quality_rules (
    rule_id SERIAL PRIMARY KEY,
    rule_name VARCHAR(100) NOT NULL,
    target_table VARCHAR(50) NOT NULL,
    check_type VARCHAR(50) NOT NULL, -- PARIDAD, HUÉRFANOS, RANGO
    severity VARCHAR(20) DEFAULT 'CRITICAL' CHECK (severity IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL'))
);

CREATE TABLE dq.data_quality_results (
    execution_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    dataset_name VARCHAR(100) NOT NULL,
    rule_name VARCHAR(100) NOT NULL,
    records_evaluated BIGINT NOT NULL,
    records_failed BIGINT NOT NULL,
    failure_percentage NUMERIC(5,2) NOT NULL, -- Porcentaje de 0.00% a 100.00%
    status VARCHAR(20) NOT NULL CHECK (status IN ('PASSED', 'WARNING', 'CRITICAL_HALT')),
    executed_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE dq.pipeline_runs (
    run_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pipeline_name VARCHAR(100) NOT NULL,
    source_layer VARCHAR(20) NOT NULL, -- BRONZE, SILVER, GOLD
    start_time TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    end_time TIMESTAMPTZ,
    status VARCHAR(20) DEFAULT 'RUNNING' CHECK (status IN ('RUNNING', 'SUCCESS', 'FAILED', 'HALTED'))
);

-- PROCEDIMIENTO DE PRUEBA POST-CARGA Y ACTIVACIÓN DE CIRCUIT BREAKER
CREATE OR REPLACE PROCEDURE dq.sp_test_post_carga_dw(IN p_run_id UUID)
LANGUAGE plpgsql AS $$
DECLARE
    v_failed_records BIGINT;
    v_total_records BIGINT;
    v_fail_pct NUMERIC(5,2);
BEGIN
    -- 1. Prueba de integridad referencial (transacciones sin cuenta válida)
    SELECT COUNT(*) INTO v_failed_records 
    FROM core.transacciones t
    LEFT JOIN core.cuentas c ON t.cuenta_origen_id = c.cuenta_id
    WHERE t.run_id = p_run_id AND c.cuenta_id IS NULL;

    SELECT COUNT(*) INTO v_total_records FROM core.transacciones WHERE run_id = p_run_id;
    
    IF v_total_records > 0 THEN
        v_fail_pct := (v_failed_records::NUMERIC / v_total_records::NUMERIC) * 100.00;
    ELSE
        v_fail_pct := 0.00;
    END IF;

    -- 2. Registrar resultado y activar Circuit Breaker
    INSERT INTO dq.data_quality_results (dataset_name, rule_name, records_evaluated, records_failed, failure_percentage, status)
    VALUES (
        'transacciones_gold', 
        'FK_CUENTA_ORIGEN_INTEGRITY', 
        v_total_records, 
        v_failed_records, 
        v_fail_pct,
        CASE WHEN v_fail_pct > 0.01 THEN 'CRITICAL_HALT' ELSE 'PASSED' END
    );

    IF v_fail_pct > 0.01 THEN
        RAISE EXCEPTION 'CIRCUIT BREAKER ACTIVADO: Tasa de falla % supera el umbral del 0.01%%', v_fail_pct;
    END IF;
END; $$;

-- -----------------------------------------------------------------------------
-- 5. ESQUEMA AI (MÓDULO GENAI, EMBEDDINGS VECTORIALES Y AUDITORÍA ÉTICA)
-- -----------------------------------------------------------------------------
CREATE TABLE ai.quejas (
    queja_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cliente_id UUID NOT NULL REFERENCES core.clientes(cliente_id),
    canal_id INT NOT NULL REFERENCES reference.canales(canal_id),
    texto_queja TEXT NOT NULL,
    embedding_queja vector(1536), -- Embeddings vectoriales para RAG con Amazon Bedrock
    fecha_queja TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE ai.ai_clasificaciones (
    clasificacion_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    queja_id UUID NOT NULL REFERENCES ai.quejas(queja_id),
    modelo_version VARCHAR(50) NOT NULL, -- Ej: Claude-3.5-Sonnet
    sentimiento VARCHAR(20) NOT NULL,
    nivel_urgencia VARCHAR(20) NOT NULL,
    sugerencia_respuesta TEXT NOT NULL,
    requiere_humano BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE ai.ai_audit_log (
    log_id BIGSERIAL PRIMARY KEY,
    clasificacion_id UUID NOT NULL REFERENCES ai.ai_clasificaciones(clasificacion_id),
    operador_humano_id VARCHAR(50) NOT NULL,
    decision_humana VARCHAR(20) NOT NULL CHECK (decision_humana IN ('APROBADO', 'MODIFICADO', 'RECHAZADO')),
    comentarios TEXT,
    fecha_revision TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- -----------------------------------------------------------------------------
-- 6. ESQUEMA ANALYTICS (DATA WAREHOUSE OLAP & VISTAS BI)
-- -----------------------------------------------------------------------------
-- DIMENSIONES Y TABLAS DE HECHOS EN STAR SCHEMA (AMAZON REDSHIFT)
CREATE TABLE analytics.dim_cliente (
    cliente_key UUID PRIMARY KEY,
    nombre VARCHAR(100),
    apellido VARCHAR(100),
    departamento VARCHAR(50),
    provincia VARCHAR(50),
    distrito VARCHAR(50),
    nivel_riesgo VARCHAR(20),
    score_riesgo INT
);

CREATE TABLE analytics.dim_producto (
    producto_key INT PRIMARY KEY,
    nombre_producto VARCHAR(100),
    familia_producto VARCHAR(30),
    moneda_id VARCHAR(3)
);

CREATE TABLE analytics.dim_canal (
    canal_key INT PRIMARY KEY,
    nombre_canal VARCHAR(50)
);

CREATE TABLE analytics.dim_sucursal (
    sucursal_key INT PRIMARY KEY,
    nombre_sucursal VARCHAR(100),
    departamento VARCHAR(50),
    provincia VARCHAR(50)
);

CREATE TABLE analytics.dim_segmento_rfm (
    segmento_rfm_key INT PRIMARY KEY,
    codigo_segmento VARCHAR(20) NOT NULL, -- CHAMPIONS, LOYAL, AT_RISK, HIBERNATING
    recencia_dias_min INT,
    recencia_dias_max INT,
    frecuencia_transacciones_min INT,
    monto_promedio_min NUMERIC(15,2),
    descripcion_accion VARCHAR(200)
);

CREATE TABLE analytics.fact_transacciones_analytics (
    fact_id BIGINT PRIMARY KEY,
    cliente_key UUID REFERENCES analytics.dim_cliente(cliente_key),
    producto_key INT REFERENCES analytics.dim_producto(producto_key),
    canal_key INT REFERENCES analytics.dim_canal(canal_key),
    sucursal_key INT REFERENCES analytics.dim_sucursal(sucursal_key),
    fecha_key INT NOT NULL,
    monto NUMERIC(15,2) NOT NULL,
    comision NUMERIC(15,2) DEFAULT 0.00
);

CREATE TABLE analytics.fact_evaluacion_riesgo_crediticio (
    evaluacion_id BIGINT PRIMARY KEY,
    cliente_key UUID NOT NULL REFERENCES analytics.dim_cliente(cliente_key),
    fecha_key INT NOT NULL,
    score_crediticio INT NOT NULL,
    probabilidad_default_pd NUMERIC(5,4) NOT NULL, -- PD (0.0000 a 1.0000)
    loss_given_default_lgd NUMERIC(5,4) NOT NULL,  -- LGD
    probabilidad_churn NUMERIC(5,4) NOT NULL,       -- Churn
    exposicion_total NUMERIC(15,2) NOT NULL,
    bucket_riesgo VARCHAR(20) NOT NULL,
    fecha_evaluacion DATE NOT NULL
);

-- VISTAS ANALÍTICAS Y MATERIALIZADAS
CREATE MATERIALIZED VIEW analytics.mv_agregados_diarios_sucursal AS
SELECT 
    s.sucursal_id,
    s.nombre_sucursal,
    s.departamento,
    DATE(t.fecha_transaccion) AS fecha,
    COUNT(t.transaccion_id) AS total_transacciones,
    SUM(t.monto) AS volumen_total,
    AVG(t.monto) AS ticket_promedio
FROM core.transacciones t
JOIN reference.sucursales s ON t.sucursal_id = s.sucursal_id
WHERE t.estado = 'COMPLETADA'
GROUP BY s.sucursal_id, s.nombre_sucursal, s.departamento, DATE(t.fecha_transaccion);

CREATE UNIQUE INDEX idx_mv_agregados_sucursal ON analytics.mv_agregados_diarios_sucursal (sucursal_id, fecha);

CREATE OR REPLACE PROCEDURE analytics.sp_refresh_materialized_views() LANGUAGE plpgsql AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY analytics.mv_agregados_diarios_sucursal;
END; $$;

CREATE VIEW analytics.vw_kpi_diarios AS
SELECT 
    DATE(t.fecha_transaccion) AS fecha,
    c.codigo_canal,
    c.nombre_canal,
    p.nombre_producto,
    COUNT(t.transaccion_id) AS total_operaciones,
    SUM(t.monto) AS facturacion_total,
    AVG(t.monto) AS ticket_promedio
FROM core.transacciones t
JOIN reference.canales c ON t.canal_id = c.canal_id
JOIN core.cuentas ct ON t.cuenta_origen_id = ct.cuenta_id
JOIN reference.productos p ON ct.producto_id = p.producto_id
WHERE t.estado = 'COMPLETADA'
GROUP BY DATE(t.fecha_transaccion), c.codigo_canal, c.nombre_canal, p.nombre_producto;

CREATE VIEW analytics.vw_morosidad_region AS
SELECT 
    cl.departamento,
    cl.provincia,
    COUNT(cr.credito_id) AS total_creditos_activos,
    SUM(cr.monto_aprobado) AS cartera_total_colocada,
    SUM(cr.saldo_capital_pendiente) AS cartera_capital_vigente,
    SUM(CASE WHEN cr.dias_mora > 30 THEN cr.saldo_capital_pendiente ELSE 0 END) AS cartera_en_mora,
    ROUND((SUM(CASE WHEN cr.dias_mora > 30 THEN cr.saldo_capital_pendiente ELSE 0 END) / NULLIF(SUM(cr.saldo_capital_pendiente), 0) * 100), 2) AS tasa_morosidad_pct
FROM core.creditos cr
JOIN core.clientes cl ON cr.cliente_id = cl.cliente_id
WHERE cr.estado IN ('VIGENTE', 'EN_MORA')
GROUP BY cl.departamento, cl.provincia;

-- -----------------------------------------------------------------------------
-- 7. PROCEDIMIENTO CENTRAL ACID () & HEALTH CHECK
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.sp_transferir_dinero(
    IN p_cuenta_origen BIGINT,
    IN p_cuenta_destino BIGINT,
    IN p_monto NUMERIC(15,2),
    IN p_canal_id INT,
    IN p_sucursal_id INT,
    IN p_idempotency_key VARCHAR(64),
    IN p_moneda VARCHAR(3)
) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
    v_saldo_origen NUMERIC(15,2);
    v_tx_id BIGINT;
BEGIN
    -- 1. Si la clave ya se procesó, devolver la transacción ORIGINAL
    --    sin crear una nueva (replay idempotente, sin efectos). Va antes que
    --    todo lo demás: el replay no debe depender del saldo actual.
    SELECT i.transaccion_id INTO v_tx_id FROM core.idempotencia i
    WHERE i.canal_id = p_canal_id AND i.idempotency_key = p_idempotency_key;
    IF FOUND THEN
        RETURN v_tx_id;
    END IF;

    -- 2. Bloqueo ordenado preventivo de Deadlocks por ID menor
    IF p_cuenta_origen < p_cuenta_destino THEN
        PERFORM 1 FROM core.cuentas WHERE cuenta_id = p_cuenta_origen FOR UPDATE;
        PERFORM 1 FROM core.cuentas WHERE cuenta_id = p_cuenta_destino FOR UPDATE;
    ELSE
        PERFORM 1 FROM core.cuentas WHERE cuenta_id = p_cuenta_destino FOR UPDATE;
        PERFORM 1 FROM core.cuentas WHERE cuenta_id = p_cuenta_origen FOR UPDATE;
    END IF;

    -- 3. Validar Saldo Disponible
    SELECT saldo_disponible INTO v_saldo_origen FROM core.cuentas WHERE cuenta_id = p_cuenta_origen;
    IF v_saldo_origen IS NULL THEN
        RAISE EXCEPTION 'CUENTA_ORIGEN_INEXISTENTE: %', p_cuenta_origen;
    END IF;
    IF v_saldo_origen < p_monto THEN
        RAISE EXCEPTION 'SALDO_INSUFICIENTE: Saldo disponible (%) es menor al monto solicitado (%)', v_saldo_origen, p_monto;
    END IF;

    -- 4. Registrar Transacción
    INSERT INTO core.transacciones (cuenta_origen_id, cuenta_destino_id, canal_id, sucursal_id, tipo_transaccion, monto, moneda_id, idempotency_key)
    VALUES (p_cuenta_origen, p_cuenta_destino, p_canal_id, p_sucursal_id, 'TRANSFERENCIA', p_monto, p_moneda, p_idempotency_key)
    RETURNING transaccion_id INTO v_tx_id;

    -- 5. Registrar idempotencia. El UNIQUE cubre la carrera entre dos llamadas
    --    concurrentes con la misma clave: la que pierde borra su fila huérfana
    --    (el INSERT de idempotencia está dentro de este bloque, el de
    --    transacciones no, así que hay que deshacerlo a mano) y devuelve la
    --    transacción ORIGINAL.
    BEGIN
        INSERT INTO core.idempotencia (canal_id, idempotency_key, transaccion_id, fecha_transaccion)
        VALUES (p_canal_id, p_idempotency_key, v_tx_id, now());
    EXCEPTION WHEN unique_violation THEN
        DELETE FROM core.transacciones WHERE transaccion_id = v_tx_id;
        SELECT i.transaccion_id INTO v_tx_id FROM core.idempotencia i
        WHERE i.canal_id = p_canal_id AND i.idempotency_key = p_idempotency_key;
        RETURN v_tx_id;
    END;

    -- 6. Inserción en Ledger Contable (Doble Partida)
    INSERT INTO core.movimientos_contables (transaccion_id, cuenta_id, tipo_movimiento, monto)
    VALUES (v_tx_id, p_cuenta_origen, 'DEBITO', p_monto);

    INSERT INTO core.movimientos_contables (transaccion_id, cuenta_id, tipo_movimiento, monto)
    VALUES (v_tx_id, p_cuenta_destino, 'CREDITO', p_monto);

    -- 7. Actualizar Saldos de forma atómica
    UPDATE core.cuentas SET saldo_actual = saldo_actual - p_monto, saldo_disponible = saldo_disponible - p_monto WHERE cuenta_id = p_cuenta_origen;
    UPDATE core.cuentas SET saldo_actual = saldo_actual + p_monto, saldo_disponible = saldo_disponible + p_monto WHERE cuenta_id = p_cuenta_destino;

    RETURN v_tx_id;
END; $$;

CREATE OR REPLACE PROCEDURE core.sp_database_health_check() LANGUAGE plpgsql AS $$
DECLARE
    v_total_cuentas BIGINT;
    v_cuentas_huerfanas BIGINT;
    v_transacciones_huerfanas BIGINT;
    v_descuadre_saldos NUMERIC(15,2);
BEGIN
    SELECT COUNT(*) INTO v_total_cuentas FROM core.cuentas;

    SELECT COUNT(*) INTO v_cuentas_huerfanas 
    FROM core.cuentas c LEFT JOIN core.clientes cl ON c.cliente_id = cl.cliente_id WHERE cl.cliente_id IS NULL;
    
    SELECT COUNT(*) INTO v_transacciones_huerfanas 
    FROM core.transacciones t LEFT JOIN core.cuentas c ON t.cuenta_origen_id = c.cuenta_id WHERE c.cuenta_id IS NULL;
    
    SELECT COALESCE(SUM(saldo_actual), 0.00) INTO v_descuadre_saldos FROM core.cuentas WHERE saldo_actual < 0.00;

    RAISE NOTICE '=== HEALTH CHECK AUDIT RESULT ===';
    RAISE NOTICE 'Total Cuentas: %', v_total_cuentas;
    RAISE NOTICE 'Cuentas Huérfanas: %', v_cuentas_huerfanas;
    RAISE NOTICE 'Transacciones Huérfanas: %', v_transacciones_huerfanas;
    RAISE NOTICE 'Sobregiros Anómalos: %', v_descuadre_saldos;
END; $$;

-- -----------------------------------------------------------------------------
-- 8. ÍNDICES COMPUESTOS B-TREE ESTRATÉGICOS DE ALTA FRECUENCIA
-- -----------------------------------------------------------------------------
CREATE INDEX idx_transacciones_fecha_cuenta ON core.transacciones (fecha_transaccion DESC, cuenta_origen_id);
CREATE INDEX idx_clientes_riesgo ON core.clientes (nivel_riesgo, score_riesgo);
CREATE INDEX idx_cuentas_cliente_estado ON core.cuentas (cliente_id, estado);

-- -----------------------------------------------------------------------------
-- 9. CONFIGURACIÓN DE SEGURIDAD RLS (ROW LEVEL SECURITY)
-- -----------------------------------------------------------------------------
ALTER TABLE core.clientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.cuentas ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.transacciones ENABLE ROW LEVEL SECURITY;

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

-- =============================================================================
-- FIN DEL SCRIPT MASTER V12.0
-- =============================================================================
