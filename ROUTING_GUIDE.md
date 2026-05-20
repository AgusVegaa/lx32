# Pulsar PCB — Guía de Routing
**Generado:** 2026-05-20  
**Estado:** ✅ Listo para rutear

---

## 1. Estado del Proyecto

| Ítem | Estado | Detalle |
|------|--------|---------|
| Schemáticos (ERC) | ✅ LIMPIO | 0 errores en 10 hojas |
| PCB netlist | ✅ IMPORTADA | 159 nets, 1850 pads |
| Footprints | ✅ COLOCADOS | 414 componentes posicionados |
| Reglas DRC (.kicad_dru) | ✅ VÁLIDAS | Sin errores de compilación |
| DRC violaciones reales | ✅ NINGUNA | 0 shorts, 0 clearance errors |
| Routing | ⏳ PENDIENTE | 556 conexiones sin rutear |
| Blind/buried vias | ⚠️ HABILITAR | Ver sección 5 |

---

## 2. Board & Stackup

**Dimensiones:** 292 × 102 mm con radios en esquinas de 2 mm  
**Grosor total:** 2.56 mm (JLCPCB JLC04161H-7628 o equivalente 16-capa)

### Asignación de Capas

| Capa | Tipo KiCad | Rol | Net/Uso |
|------|-----------|-----|---------|
| F.Cu | signal | Señales top + GND pour | GND zone fill ✅ |
| In1.Cu | **power** | Plano GND | GND fill ✅ |
| In2.Cu | signal | Señales internas (HALL, SRAM addr) | Sin routing |
| In3.Cu | **power** | Plano +1V0 (VCCint FPGA) | +1V0 fill ✅ |
| In4.Cu | signal | Señales internas (SRAM data) | Sin routing |
| In5.Cu | **power** | Plano +1V8 (VCCaux FPGA) | +1V8 fill ✅ |
| In6.Cu | signal | Señales internas (ADC SPI) | Sin routing |
| In7.Cu | **power** | Plano GND (refuerzo bajo FPGA) | GND fill ✅ |
| In8.Cu | **power** | Plano GND (digital) | GND fill ✅ |
| In9.Cu | signal | Señales internas (MUX, misc) | Sin routing |
| In10.Cu | **power** | Plano +1V0_MGT (FPGA GTX) | +1V0_MGT fill ✅ |
| In11.Cu | signal | Señales internas (FPGA IO misc) | Sin routing |
| In12.Cu | **power** | Plano +3V3 (lógica periférica) | +3V3 fill ✅ |
| In13.Cu | signal | Señales internas (I2C, SPI, FIDO2) | Sin routing |
| In14.Cu | **power** | Plano GND (analógico) | GND fill ✅ |
| B.Cu | signal | Señales bottom + GND pour | GND zone fill ✅ |

> **Capas de señal disponibles:** F.Cu, In2, In4, In6, In9, In11, In13, B.Cu (8 capas de señal)

---

## 3. Design Rules (DRC)

Archivo: `pulsar .kicad_dru`

| Regla | Clearance min | Track min | Via min |
|-------|--------------|-----------|---------|
| **Default** | 0.09 mm | 0.09 mm | Ø 0.30 mm |
| **USB_Signals** (USB_DP_RAW, USB_DM_RAW) | 0.12 mm | 0.15 mm (opt 0.17) | — |
| **Power_Nets** (GND, +3V3, +1V0, +1V8, +1V0_MGT) | 0.20 mm | 0.30 mm | — |
| **ISO_Creepage** (FIDO2_SCL, FIDO2_SDA) | 0.50 mm | — | — |

Via constraints (Default):
- Diámetro mínimo: 0.30 mm
- Tamaño de hole mínimo: 0.15 mm
- Annular ring mínimo: 0.075 mm

---

## 4. Inventario de Nets (159 total)

### Power Nets (9) — servidas por planos, solo necesitan vías de stitching
| Net | Plano | Pads |
|-----|-------|------|
| GND | F.Cu, In1, In7, In8, In14, B.Cu | 544 |
| +3V3 | In12.Cu | 210 |
| +1V0 | In3.Cu | 55 |
| +1V0_MGT | In10.Cu | 25 |
| +1V8 | In5.Cu | 26 |
| +1V2_MGT | — (traza) | 17 |
| VBUS | — (traza) | 24 |
| +2V5_REF | — (traza) | 12 |
| +2V5_MGT | — (traza) | 10 |

### Señales a Rutear (150 nets, 556 conexiones)

#### HALL Sensors — 61 nets (HALL0 … HALL60)
- Fuente: multiplexores U_MUX0–U_MUX3 → FPGA
- Recomendación: In2.Cu o In4.Cu, trazas 0.10–0.12 mm, grid 0.1 mm

#### SRAM Bus — 44 nets
- Address: SRAM_A0 … SRAM_A19 (20 líneas)
- Data: SRAM_D0 … SRAM_D15 (16 líneas)
- Control: SRAM_CE_N, SRAM_CE2_N, SRAM_OE_N, SRAM_WE_N (4 líneas)
- Recomendación: In4.Cu o In6.Cu, trazas 0.10 mm, longitudes igualadas en grupos

#### ADC SPI — 16 nets
- ADC1–4: CNV, SCK, SDI, SDO (×4 canales)
- ⚠️ Señales críticas de timing — igualar longitudes por canal (±0.5 mm)
- Recomendación: In6.Cu, trazas 0.12 mm

#### MUX Control — 16 nets
- MUX0–3: D, EN, OUT (×4 grupos = 12 nets)
- Shared: MUX_A0, MUX_A1, MUX_A2, MUX_A3 (4 nets)
- Recomendación: In9.Cu, trazas 0.10 mm

#### Clocks — 3 nets ⚠️ CRÍTICAS
| Net | Frecuencia | Fuente → Destino |
|-----|-----------|-----------------|
| CLK_50M | 50 MHz | Y2 → FPGA MRCC | 
| CLK_48M | 48 MHz | Y1 → STM32 / FPGA |
| SWCLK | DC | Debug header |
- ⚠️ Rutear primero, longitud corta, no cruzar planos de potencia fragmentados
- Recomendación: F.Cu o B.Cu, trazas 0.12 mm, sin vías si posible

#### USB — 5 nets ⚠️ CRÍTICAS (par diferencial)
| Net | Descripción |
|-----|------------|
| USB_DP_RAW | D+ (par diferencial) |
| USB_DM_RAW | D− (par diferencial) |
| CC1 | Configuration Channel 1 |
| CC2 | Configuration Channel 2 |
| VBUS | USB Power (5V) |
- ⚠️ DP/DM deben ir como par diferencial: trazas 0.17 mm, clearance 0.12 mm, longitud igualada (±0.1 mm), sin cruzar GND cuts
- Recomendación: F.Cu directo J1 → U_STM, sin capas internas

#### Flash SPI — 4 nets
| Net | Descripción |
|-----|------------|
| FLASH_CS | Chip select |
| FLASH_SCK | Clock SPI |
| FLASH_MOSI | Master Out |
| FLASH_MISO | Master In |
- Recomendación: In13.Cu, trazas 0.12 mm

#### FIDO2 I2C — 2 nets ⚠️ CREEPAGE 0.5mm
| Net | Descripción |
|-----|------------|
| FIDO2_SCL | I2C Clock |
| FIDO2_SDA | I2C Data |
- ⚠️ Clearance mínimo 0.5 mm entre estas señales y cualquier otra
- Recomendación: In13.Cu, trazas 0.12 mm

#### Debug/Misc — 4 nets
- I2C_SCL, I2C_SDA (bus I2C general)
- SWDIO, NRST_STM (debug STM32)

---

## 5. Configuración de Vías (IMPORTANTE)

El PCB está configurado como 16 capas pero las vías ciegas/enterradas deben habilitarse en KiCad antes de rutear:

**Pasos en KiCad:**
1. `File → Board Setup → Design Rules → Constraints`
2. Habilitar: ☑ "Allow blind/buried vias"
3. Habilitar: ☑ "Allow micro-vias" (opcional, para BGA fanout si JLCPCB lo permite)
4. Click OK

**Vías permitidas por JLCPCB (16L HDI):**

| Tipo | Layers | Drill | Pad Ø |
|------|--------|-------|-------|
| Through-hole | F.Cu–B.Cu | 0.15 mm | 0.30 mm |
| Blind (top) | F.Cu–In1.Cu | 0.10 mm | 0.20 mm |
| Blind (bottom) | B.Cu–In14.Cu | 0.10 mm | 0.20 mm |
| Buried | In1–In8 (inner pairs) | 0.10 mm | 0.20 mm |

> **Nota:** Las blind/buried vías son más caras. Usar through-hole donde sea posible, blind/buried solo para BGA fanout del FPGA y rutas críticas.

---

## 6. Orden de Routing Recomendado

1. **GND stitching vias** — añadir vías de GND bajo el FPGA BGA para conectar los planos internos (In1, In7, In8, In14) con F.Cu y B.Cu. Grid 1.0 mm bajo el BGA.

2. **Power decoupling** — conectar los condensadores de desacoplo a sus respectivos planos de potencia. Vías cortas, directamente a pad.

3. **Clocks** (CLK_50M, CLK_48M) — trazas cortas, sin vías si posible, en F.Cu.

4. **USB DP/DM** — par diferencial, desde J1 hasta U_STM, en F.Cu.

5. **ADC SPI** (ADC1–4) — igualar longitudes por canal.

6. **Flash SPI + FIDO2 I2C** — señales relativamente simples.

7. **SRAM bus** — 44 líneas, usar In4/In6, agrupar address y data.

8. **MUX control** — 16 líneas simples.

9. **HALL sensors** (61 nets) — mayor cantidad de señales, usar In2/In4.

10. **Fill All Zones** — rellenar todos los planos al final de cada sesión de routing (Edit → Fill All Zones o `B`).

---

## 7. Warnings del DRC (no son errores, no bloquean fabricación)

Estos warnings aparecen en el DRC pero son todos cosméticos/esperados:

| Warning | Causa | Acción |
|---------|-------|--------|
| "Isolated copper fill" en In1/In7/In8/In14 | Planos GND sin vías de stitching aún | Se resuelve al añadir vías GND |
| "Footprint not in library" (SRAM_SOJ-44, etc.) | Footprints personalizados | Ninguna, son correctos |
| "Library 'Device' not found" | Path de librería no configurado | No afecta fabricación |
| "Footprint does not match library copy" | Footprints modificados localmente | Ninguna |

---

## 8. Archivos del Proyecto

```
/Users/axel/Pulsar/pcb/pulsar/
├── pulsar .kicad_pcb        ← PCB principal (KiCad 10)
├── pulsar .kicad_sch        ← Schemático raíz
├── pulsar .kicad_dru        ← Reglas DRC custom
├── pulsar .kicad_pro        ← Proyecto KiCad
├── adc.kicad_sch            ← Hoja ADC (16912 líneas)
├── fido2.kicad_sch          ← Hoja FIDO2
├── fpga.kicad_sch           ← Hoja FPGA root
├── fpga_a1.kicad_sch        ← FPGA Bank A1 (14964 líneas)
├── fpga_b2.kicad_sch        ← FPGA Bank B2 (20408 líneas)
├── fpga_c3.kicad_sch        ← FPGA Bank C3
├── hall.kicad_sch           ← Hall sensors (44955 líneas)
├── power.kicad_sch          ← Power management
└── usb.kicad_sch            ← USB
```

---

## 9. Checklist Pre-Routing

- [x] ERC limpio en todos los schemáticos
- [x] Netlist importada al PCB
- [x] 414 footprints colocados
- [x] Board outline definido (292×102 mm)
- [x] 16-layer stackup configurado
- [x] Planos de potencia (10 zones) rellenos
- [x] Reglas DRC (.kicad_dru) compilando sin errores
- [x] PCB guardado
- [ ] Habilitar blind/buried vias en Board Setup
- [ ] Configurar netclasses adicionales (USB_HS, CLOCK) si se desea
- [ ] Rutear 556 conexiones

---

*Generado automáticamente por análisis de `pulsar .kicad_pcb` y schemáticos.*
