"""Valida las reglas de coherencia de la entrega demo (§4.5) + RAW + catálogo.
Uso: python pruebas/validar_demo.py [dir_entrega]
Solo librería estándar. Streaming en archivos grandes.
"""
import csv
import json
import os
import sys
from collections import Counter

BASE = sys.argv[1] if len(sys.argv) > 1 else "entrega"
CL = os.path.join(BASE, "clean")
RW = os.path.join(BASE, "raw")
errs = []


def check(c, m):
    if not c:
        errs.append(m)


def rows(name, d=CL):
    with open(os.path.join(d, name), encoding="utf-8") as f:
        yield from csv.DictReader(f)


man = json.load(open(os.path.join(BASE, "metadata_manifest.json")))
mc = man["datasets"]["clean"]["master_counts"]
rawm = man["datasets"]["raw"]

GEO_VALIDAS = {
    ("Lima", "Lima", "Miraflores"), ("Lima", "Lima", "San Isidro"),
    ("Lima", "Lima", "Santiago de Surco"), ("Lima", "Lima", "La Molina"),
    ("Lima", "Lima", "San Borja"), ("Arequipa", "Arequipa", "Yanahuara"),
    ("Arequipa", "Arequipa", "Cayma"), ("La Libertad", "Trujillo", "Victor Larco"),
    ("La Libertad", "Trujillo", "Trujillo"), ("Piura", "Piura", "Piura"),
    ("Piura", "Piura", "Castilla"), ("Cusco", "Cusco", "Wanchaq"),
    ("Cusco", "Cusco", "Cusco"), ("Junin", "Huancayo", "Huancayo"),
    ("Junin", "Huancayo", "El Tambo"), ("Lambayeque", "Chiclayo", "Chiclayo"),
    ("Lambayeque", "Chiclayo", "La Victoria"), ("Ancash", "Huaraz", "Huaraz"),
    ("Ancash", "Huaraz", "Independencia"), ("Callao", "Callao", "Callao"),
    ("Callao", "Callao", "Bellavista"),
}

cli = list(rows("clientes.csv"))
cta = list(rows("cuentas.csv"))
tar = list(rows("tarjetas.csv"))
sol = list(rows("solicitudes.csv"))
cre = list(rows("creditos.csv"))

check(len(cli) == mc["clientes"] + 1, "clientes 8000+1 banco")
check(len(cta) == mc["cuentas"], "cuentas 12000")
check(len(tar) == mc["tarjetas"], "tarjetas")
check(len(sol) == mc["solicitudes"], "solicitudes")
check(len(cre) == mc["creditos"], "creditos")

# Regla: cuentas únicas secuenciales, 1-3 por cliente, ninguno sin cuenta
nums = [r["numero_cuenta"] for r in cta]
check(len(set(nums)) == len(nums), "numero_cuenta UNIQUE")
check(all(n.startswith("191-") for n in nums), "formato numero_cuenta")
por_cli = Counter(r["cliente_id"] for r in cta)
cli_ids = {r["cliente_id"] for r in cli}
check(set(por_cli) == cli_ids, "ningun cliente sin cuenta")
check(all(1 <= v <= 3 for k, v in por_cli.items() if k != cli[-1]["cliente_id"]),
      "1-3 cuentas por cliente persona")

# Regla: geografía válida
check(all((r["departamento"], r["provincia"], r["distrito"]) in GEO_VALIDAS for r in cli),
      "geo clientes valida")
check(all(300 <= int(r["score_riesgo"]) <= 850 for r in cli), "score rango")
scores = [int(r["score_riesgo"]) for r in cli[:-1]]
check(600 <= sum(scores) / len(scores) <= 700, "score media ~650 (%.1f)" % (sum(scores) / len(scores)))
check(len({r["dni_hash"] for r in cli}) == len(cli), "dni_hash unico clean")

# Segmento derivado del promedio de aperturas
ap_por_cli = {}
for r in cta:
    ap_por_cli.setdefault(r["cliente_id"], []).append(float(r["saldo_inicial"]))
for r in cli[:-1]:
    avg = sum(ap_por_cli[r["cliente_id"]]) / len(ap_por_cli[r["cliente_id"]])
    esp = "MASIVO" if avg < 3000 else ("PREFERENTE" if avg <= 30000 else "PATRIMONIAL")
    if r["segmento_cliente"] != esp:
        check(False, "segmento incoherente")
        break
else:
    check(True, "segmento")

# Tarjetas: débito con cuenta y sin línea; crédito al revés + disponible cuadra
for r in tar:
    if r["tipo_tarjeta"] == "DEBITO":
        check(r["cuenta_id"] != "" and float(r["limite_credito"]) == 0, "debito")
    else:
        check(r["cuenta_id"] == "" and float(r["limite_credito"]) > 0, "credito")
        check(abs(float(r["saldo_disponible"]) - (float(r["limite_credito"]) - float(r["saldo_utilizado"]))) < 0.01,
              "disponible tarjeta")
check(len({r["token_tarjeta_hash"] for r in tar}) == len(tar), "token unico")

# Créditos: aprobación, mora 8-12%, saldo <= aprobado
check(sum(1 for r in sol if r["estado"] == "APROBADO") == mc["creditos"], "aprobadas=2000")
mora = sum(1 for r in cre if r["estado"] == "EN_MORA")
check(8 <= mora / len(cre) * 100 <= 12, "mora 8-12%% (%.1f)" % (mora / len(cre) * 100))
check(all(float(r["saldo_capital_pendiente"]) <= float(r["monto_aprobado"]) for r in cre),
      "saldo<=aprobado")
check(all(r["bucket_riesgo"] in ("AL_DIA", "1_30_DIAS", "31_60_DIAS", "61_90_DIAS", "90_MAS_DIAS") for r in cre),
      "buckets")


def bucket_esperado(d):
    # Cortes SBS Res. 11356-2008 aplicados sobre dias_mora.
    if d <= 8:
        return "AL_DIA"
    if d <= 30:
        return "1_30_DIAS"
    if d <= 60:
        return "31_60_DIAS"
    if d <= 120:
        return "61_90_DIAS"
    return "90_MAS_DIAS"


# 7.8.2: sin casos por encima de 60 dias (antes habia de 111 y 238)
dmax_mora = max(int(r["dias_mora"]) for r in cre)
check(dmax_mora <= 60, "dias_mora tope 60 (%d)" % dmax_mora)
# 7.8.4: el rotulo del bucket tiene que ser la categoria SBS del dias_mora,
# no un mapeo propio. Con el tope de 60 solo se ven los tres primeros.
mal_bucket = [r for r in cre if r["bucket_riesgo"] != bucket_esperado(int(r["dias_mora"]))]
check(not mal_bucket, "bucket = corte SBS (%d malos, p.ej. %s)" % (
    len(mal_bucket), (mal_bucket[0]["credito_id"] + "/" + mal_bucket[0]["dias_mora"]) if mal_bucket else "-"))
check(all(r["bucket_riesgo"] in ("AL_DIA", "1_30_DIAS", "31_60_DIAS") for r in cre),
      "solo buckets alcanzables")
# 7.8.3: cartera solo consumo (CRED_PERSONAL = producto 9)
check(all(r["producto_id"] == "9" for r in cre), "creditos solo producto 9")
check(all(r["producto_id"] == "9" for r in sol), "solicitudes solo producto 9")

# Cuotas: 12-36 por crédito, total = cap+int+seg
ncuo = Counter()
mal_cuota = 0
for r in rows("cuotas.csv"):
    ncuo[r["credito_id"]] += 1
    if abs(float(r["monto_total_cuota"]) - (float(r["monto_capital"]) + float(r["monto_interes"]) + float(r["seguro_desgravamen"]))) > 0.005:
        mal_cuota += 1
check(all(12 <= v <= 36 for v in ncuo.values()), "cuotas 12-36")
check(mal_cuota == 0, "cuota total exacta")
check(sum(ncuo.values()) == mc["cuotas"], "total cuotas")

# Pagos: monto>0, cuota y canal válidos
cuo_ids = set()
for r in rows("cuotas.csv"):
    cuo_ids.add(r["cuota_id"])
npag = 0
for r in rows("pagos.csv"):
    npag += 1
    check(float(r["monto_pagado"]) > 0 and r["cuota_id"] in cuo_ids and r["canal_id"] in {str(i) for i in range(1, 8)},
          "pagos coherence")
    if errs and errs[-1] == "pagos coherence":
        break
check(npag == mc["pagos"], "total pagos %d" % npag)

# Transacciones (streaming) + ledger
mon_de = {r["cuenta_id"]: r["moneda_id"] for r in cta}
DIG = {"1", "2", "5", "7"}
ntx = ncomp = 0
dmin = dmax = None
for r in rows("transacciones.csv"):
    ntx += 1
    check(r["moneda_id"] == mon_de[r["cuenta_origen_id"]], "moneda origen")
    check((r["cuenta_destino_id"] != "") == (r["tipo_transaccion"] in ("TRANSFERENCIA", "TRANSFERENCIA_PLIN")),
          "destino solo transferencias")
    check((r["sucursal_id"] == "10") == (r["canal_id"] in DIG), "digital->sucursal 10")
    if r["estado"] == "COMPLETADA":
        ncomp += 1
    if dmin is None or r["fecha_transaccion"] < dmin:
        dmin = r["fecha_transaccion"]
    if dmax is None or r["fecha_transaccion"] > dmax:
        dmax = r["fecha_transaccion"]
    # comisión por regla
    m, c = float(r["monto"]), float(r["comision"])
    if r["tipo_transaccion"] == "COMPRA_POS":
        ok = abs(c - round(m * 0.015, 2)) < 0.011
    elif r["tipo_transaccion"] == "PAGO_QR":
        ok = abs(c - (0.50 if r["moneda_id"] == "PEN" else 0.15)) < 0.001
    elif r["tipo_transaccion"] == "RETIRO" and r["canal_id"] == "4":
        ok = abs(c - (2.00 if r["moneda_id"] == "PEN" else 1.00)) < 0.001
    else:
        ok = c == 0
    check(ok, "comision")
    if len(errs) > 40:
        break
check(ntx == mc["transacciones"], "total tx")
check(dmin[:10] >= "2025-10-01" and dmax[:10] <= "2026-09-30", "ventana %s..%s" % (dmin[:10], dmax[:10]))

net = {}
sd = sc = 0.0
nmv = 0
por_tx = {}
for r in rows("movimientos.csv"):
    nmv += 1
    monto = float(r["monto"])
    if r["tipo_movimiento"] == "DEBITO":
        net[r["cuenta_id"]] = net.get(r["cuenta_id"], 0.0) - monto
        sd += monto
    else:
        net[r["cuenta_id"]] = net.get(r["cuenta_id"], 0.0) + monto
        sc += monto
    por_tx.setdefault(r["transaccion_id"], []).append(r["tipo_movimiento"])
check(abs(sd - sc) < 0.01, "cuadratura %.2f vs %.2f" % (sd, sc))
check(all(sorted(v) == ["CREDITO", "DEBITO"] for v in por_tx.values()), "2 asientos/tx")
# saldo = inicial + neto ledger, sin negativos
for r in cta:
    esp = round(float(r["saldo_inicial"]) + net.get(r["cuenta_id"], 0.0), 2)
    check(abs(float(r["saldo_actual"]) - esp) < 0.01, "saldo ledger %s" % r["cuenta_id"])
    check(float(r["saldo_actual"]) >= 0, "sin sobregiros")
    if len(errs) > 60:
        break
lc = man["datasets"]["clean"]["ledger_control"]
check(lc["balanced"] and abs(lc["sum_debitos"] - round(sd, 2)) < 0.01, "manifest ledger")

# Idempotencia: claves únicas y 1:1 con completadas
idem = list(rows("idempotencia.csv"))
check(len(idem) == ncomp, "idem=completadas")
check(len({(r["canal_id"], r["idempotency_key"]) for r in idem}) == len(idem), "idem unique")

# RAW + catálogo
cat = list(rows("catalogo_errores.csv", d=BASE))
conteo = Counter((r["tabla"], r["tipo_error"]) for r in cat)
esp_tx = rawm["errores_transacciones"]
nombres = {"duplicadas": "duplicada", "monto_no_positivo": "monto_no_positivo",
           "moneda_invalida": "moneda_invalida", "fecha_futura": "fecha_futura",
           "origen_inexistente": "origen_inexistente", "nulo_monto": "nulo_monto",
           "nulo_cuenta": "nulo_cuenta", "nulo_fecha": "nulo_fecha"}
for k, v in esp_tx.items():
    check(conteo[("transacciones", nombres[k])] == v, "catalogo tx %s" % k)
for k, v in rawm["errores_cruzados"].items():
    tabla = {"dni_duplicado": "clientes", "saldo_mayor_aprobado": "creditos",
             "ledger_descuadrado": "movimientos"}[k]
    check(conteo[(tabla, k)] == v, "catalogo %s" % k)
check(abs(rawm["tasa_error_transacciones_pct"] - round(sum(esp_tx.values()) / mc["transacciones"] * 100, 2)) < 1e-9,
      "tasa raw")

print("ERRORES:", len(errs))
for e in errs[:30]:
    print(" -", e)
print("OK" if not errs else "FALLO")
