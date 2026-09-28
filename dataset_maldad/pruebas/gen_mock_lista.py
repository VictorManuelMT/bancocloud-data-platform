"""Regenera los mocks de la app (gestor-web/src/mocks/*.json) desde ./entrega/.

Uso (desde dataset_maldad/):
    python pruebas/gen_mock_lista.py

lista.json  -> creditos con dias_mora entre 1 y 60, sin los que estan en
               cuarentena (la pestana "No contactar" dice que NO estan en la
               lista de hoy; antes habia 4 que aparecian en ambos archivos).
               Ordenado por prioridad desc.
cuarentena.json -> filas de entrega/catalogo_errores.csv con tabla=creditos.

Derivaciones (verificadas 1 a 1 contra los mocks previos, 0 desvios):
    cliente          = nombre + ' ' + apellido
    saldo_expuesto   = saldo_capital_pendiente
    cuotas_impagas   = count(cuotas con estado VENCIDO)
    puntaje_riesgo   = base[bucket] + 5 * (cuotas_impagas - 1)
    prioridad        = saldo_expuesto * puntaje_riesgo
    motivo_ia        = texto_nota de la ultima gestion (vacio si no hay)
    canal_contacto   = canal_contacto de la ultima gestion
    fecha_gestion    = fecha_gestion de la ultima gestion
    accion           = una por bucket (ver ACCION)
    cliente (cuarentena) = inicial del nombre
"""
import csv
import json
import os
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # dataset_maldad/
ENT = os.path.join(ROOT, "entrega")
MOCKS = os.path.join(os.path.dirname(ROOT), "gestor-web", "src", "mocks")

# base del puntaje por bucket (los cortes SBS no cambian el puntaje)
BASE_PUNTAJE = {"AL_DIA": 15, "1_30_DIAS": 40, "31_60_DIAS": 65,
                "61_90_DIAS": 85, "90_MAS_DIAS": 100}
ACCION = {
    "AL_DIA": "Recordatorio automatico",
    "1_30_DIAS": "Llamada call center hoy",
    "31_60_DIAS": "Gestor asignado + evaluar refinanciacion",
    "61_90_DIAS": "Gestor asignado + acuerdo de pago",
    "90_MAS_DIAS": "Preparar cobranza judicial",
}


def rows(path):
    with open(path, encoding="utf-8", newline="") as f:
        yield from csv.DictReader(f)


def main():
    cre = list(rows(os.path.join(ENT, "clean", "creditos.csv")))
    cli = {r["cliente_id"]: r for r in rows(os.path.join(ENT, "clean", "clientes.csv"))}
    cat = list(rows(os.path.join(ENT, "catalogo_errores.csv")))

    impagas = Counter(
        r["credito_id"]
        for r in rows(os.path.join(ENT, "clean", "cuotas.csv"))
        if r["estado"] == "VENCIDO")

    # ultima gestion por credito (la mas reciente; con empate gana la ultima)
    ult = {}
    for g in rows(os.path.join(ENT, "clean", "gestiones_cobranza.csv")):
        if g["credito_id"] not in ult or g["fecha_gestion"] >= ult[g["credito_id"]]["fecha_gestion"]:
            ult[g["credito_id"]] = g

    cat_creditos = [r for r in cat if r["tabla"] == "creditos"]
    cua_ids = {r["fila_id"] for r in cat_creditos}
    cua = [{
        "credito_id": int(r["fila_id"]),
        "cliente": cli[next(c["cliente_id"] for c in cre
                            if c["credito_id"] == r["fila_id"])]["nombre"][0],
        "saldo_expuesto": float(next(c["saldo_capital_pendiente"] for c in cre
                                     if c["credito_id"] == r["fila_id"])),
        "tipo_error": r["tipo_error"],
        "regla": r["regla_esperada"],
    } for r in cat_creditos]

    lista, fuera = [], 0
    for c in cre:
        dm = int(c["dias_mora"])
        if not 1 <= dm <= 60:
            continue
        if c["credito_id"] in cua_ids:
            fuera += 1
            continue
        cid = c["credito_id"]
        p = cli[c["cliente_id"]]
        n = impagas.get(cid, 0)
        punt = BASE_PUNTAJE[c["bucket_riesgo"]] + 5 * (n - 1)
        saldo = float(c["saldo_capital_pendiente"])
        g = ult.get(cid)
        lista.append({
            "credito_id": int(cid),
            "cliente": p["nombre"] + " " + p["apellido"],
            "departamento": p["departamento"],
            "saldo_expuesto": saldo,
            "dias_mora": dm,
            "bucket_riesgo": c["bucket_riesgo"],
            "cuotas_impagas": n,
            "puntaje_riesgo": punt,
            "prioridad": round(saldo * punt, 2),
            "accion_recomendada": ACCION[c["bucket_riesgo"]],
            "motivo_ia": (g or {}).get("texto_nota") or "",
            "canal_contacto": (g or {}).get("canal_contacto") or "",
            "fecha_gestion": (g or {}).get("fecha_gestion") or "",
        })
    lista.sort(key=lambda r: -r["prioridad"])

    for name, data in (("lista.json", lista), ("cuarentena.json", cua)):
        with open(os.path.join(MOCKS, name), "w", encoding="utf-8") as f:
            json.dump(data, f, indent=1, ensure_ascii=False)
        print("%s: %d filas" % (name, len(data)))
    print("fuera de lista por estar en cuarentena: %d" % fuera)


if __name__ == "__main__":
    main()
