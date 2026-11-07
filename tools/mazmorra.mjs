// La Grieta (muestra de ambiente): primera mazmorra jugable, SOLO en el lugar de desarrollo.
// No es el mundo definitivo (Alba, el Faro y las Grietas finales llegan en la Fase 11): sirve para ver
// cómo luce y se siente el movimiento y el combate en un lugar con ambiente.
//
// Está bajo tierra (Y = -200), cerrada por todos lados, así que su luz es la de sus antorchas y cristales.
// Recorrido, con medidas que salen del movimiento real (salto 8,5 · doble salto 15,5 · Paso 14):
//   A. Umbral (aparición) → B. pasillo → C. Abismo: salto de 8 y salto + Paso de 16; caer al foso te
//   devuelve al borde de inicio (GrietaService) → D. Ascenso: repisas de 6, 13, 20 y 28 (salto y doble salto) →
//   E. Sala del Guardián: el compañero de combate espera en el centro.

import { part, sign, folder, rotY, facing } from './mapa.mjs';

const O = [0, -200, 0]; // origen de la mazmorra
const P = (x, y, z) => [O[0] + x, O[1] + y, O[2] + z];

const STONE = [78, 76, 72];
const STONE_DARK = [54, 52, 50];
const FLOOR = [92, 88, 82];
const WOOD = [92, 64, 40];

// Caja por esquinas (más fácil de leer que centro + tamaño)
function box(name, [x0, y0, z0], [x1, y1, z1], color = STONE, material = 'Slate', extra = {}) {
  return part({
    name,
    size: [Math.abs(x1 - x0), Math.abs(y1 - y0), Math.abs(z1 - z0)],
    pos: P((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
    color,
    material,
    ...extra,
  });
}

// Pared perpendicular a Z (en z), de x0 a x1 y de y0 a y1, con una puerta opcional
function wallZ(name, z, x0, x1, y0, y1, door) {
  const t = 1; // medio grosor
  if (!door) return [box(name, [x0, y0, z - t], [x1, y1, z + t])];
  const [dx0, dx1, dy0, dy1] = door;
  const pieces = [];
  if (dx0 > x0) pieces.push(box(name + 'Izq', [x0, y0, z - t], [dx0, y1, z + t]));
  if (dx1 < x1) pieces.push(box(name + 'Der', [dx1, y0, z - t], [x1, y1, z + t]));
  if (dy0 > y0) pieces.push(box(name + 'Bajo', [dx0, y0, z - t], [dx1, dy0, z + t]));
  if (dy1 < y1) pieces.push(box(name + 'Dintel', [dx0, dy1, z - t], [dx1, y1, z + t]));
  return pieces;
}

// Pared perpendicular a X (en x)
function wallX(name, x, z0, z1, y0, y1) {
  return [box(name, [x - 1, y0, z0], [x + 1, y1, z1])];
}

// Sala cerrada: piso (tope en y0), techo y paredes laterales. Las paredes frontal y trasera van aparte.
function shell(name, x0, x1, z0, z1, y0, height, floorMaterial = 'Cobblestone') {
  return [
    box(name + 'Piso', [x0, y0 - 8, z0], [x1, y0, z1], FLOOR, floorMaterial), // 8 de grosor: nada lo atraviesa
    box(name + 'Techo', [x0, y0 + height, z0], [x1, y0 + height + 2, z1], STONE_DARK, 'Rock'),
    ...wallX(name + 'ParedO', x0 - 1, z0, z1, y0 - 2, y0 + height + 2),
    ...wallX(name + 'ParedE', x1 + 1, z0, z1, y0 - 2, y0 + height + 2),
  ];
}

// Antorcha en una pared: soporte de madera, llama que brilla, luz cálida con sombras y fuego
function torch(name, x, y, z, side) {
  const out = side; // +1: pared este (la antorcha sobresale hacia -X), -1: pared oeste
  return [
    part({ name: name + 'Soporte', size: [0.5, 1.8, 0.5], pos: P(x - out * 0.4, y, z), color: WOOD, material: 'Wood', collide: false }),
    part({
      name: name + 'Llama',
      size: [0.7, 0.7, 0.7],
      pos: P(x - out * 0.4, y + 1.2, z),
      color: [255, 150, 60],
      material: 'Neon',
      collide: false,
      children: [
        {
          className: 'PointLight',
          name: 'Luz',
          props: [
            ['float', 'Brightness', 2.2],
            ['float', 'Range', 20],
            ['color3', 'Color', [1, 0.62, 0.32]],
            ['bool', 'Shadows', true],
          ],
          children: [],
        },
        {
          className: 'Fire',
          name: 'Fuego',
          props: [
            ['float', 'size_xml', 2],
            ['float', 'heat_xml', 6],
            ['color3', 'Color', [1, 0.55, 0.2]],
            ['color3', 'SecondaryColor', [0.9, 0.25, 0.05]],
          ],
          children: [],
        },
      ],
    }),
  ];
}

// Cristal del Eco: brilla en color frío (la "resonancia" de la Grieta)
function crystal(name, x, y, z, h = 4, color = [90, 220, 255], angle = 0) {
  return part({
    name,
    size: [1.2, h, 1.2],
    pos: P(x, y + h / 2, z),
    rot: rotY(angle),
    color,
    material: 'Neon',
    collide: false,
    children: [
      {
        className: 'PointLight',
        name: 'Luz',
        props: [
          ['float', 'Brightness', 1.6],
          ['float', 'Range', 16],
          ['color3', 'Color', color.map((c) => c / 255)],
          ['bool', 'Shadows', false],
        ],
        children: [],
      },
    ],
  });
}

function pillar(name, x, z, y0, height) {
  return box(name, [x - 1.4, y0, z - 1.4], [x + 1.4, y0 + height, z + 1.4], STONE_DARK, 'Granite');
}

export function buildDungeon() {
  const items = [];

  // ---------- A. Umbral (aparición) ----------
  items.push(...shell('Umbral', -12, 12, 0, 40, 0, 18));
  items.push(...wallZ('UmbralFondo', -1, -14, 14, -2, 20));
  items.push(...wallZ('UmbralSalida', 41, -14, 14, -2, 20, [-5, 5, 0, 12]));
  for (const z of [10, 26]) {
    items.push(pillar('Columna', -8.5, z, 0, 18), pillar('Columna', 8.5, z, 0, 18));
  }
  for (const z of [6, 18, 32]) {
    items.push(...torch('AntorchaO', -12, 7, z, -1), ...torch('AntorchaE', 12, 7, z, 1));
  }
  // Fragmentos de Eco flotando sobre la entrada
  items.push(crystal('Fragmento', -3, 12, 20, 2, [150, 120, 255], 30), crystal('Fragmento', 4, 13.5, 24, 1.6, [150, 120, 255], 70));
  items.push(crystal('Fragmento', 0.5, 11, 14, 1.2, [150, 120, 255], 10));
  items.push(
    part({
      name: 'Aparicion',
      className: 'SpawnLocation',
      size: [8, 1, 8],
      pos: P(0, 0.5, 6),
      rot: rotY(180), // el personaje aparece mirando hacia +Z (hacia el pasillo), como en el laboratorio
      color: [60, 50, 90],
      material: 'Marble',
      extra: [
        ['bool', 'Neutral', true],
        ['int', 'Duration', 0],
      ],
    }),
  );
  // Instructor del tutorial, al fondo de la sala de entrada (lejos de la aparición: no ataca al llegar)
  {
    const pos = P(0, 3.2, 34);
    items.push(part({ name: 'PuntoSparring_Instructor', size: [1, 1, 1], pos, rot: facing(pos, P(0, 3.2, 0)), transparency: 1, collide: false, color: [255, 255, 255] }));
  }
  items.push(sign('Bienvenida', 'LA GRIETA · muestra de ambiente · sigue las antorchas', P(0, 14, 39.8), P(0, 14, 0), [22, 3, 0.4]));

  // ---------- B. Pasillo ----------
  items.push(box('PasilloPiso', [-5, -8, 41], [5, 0, 61], FLOOR, 'Cobblestone'));
  items.push(box('PasilloTecho', [-5, 12, 41], [5, 14, 61], STONE_DARK, 'Rock'));
  items.push(...wallX('PasilloParedO', -6, 41, 61, -2, 14), ...wallX('PasilloParedE', 6, 41, 61, -2, 14));
  items.push(...torch('AntorchaPasillo', -5, 6, 51, -1));
  // Enemigo común (experimental): Latido, a ritmo fijo. Enseña el desvío perfecto.
  const enemy = (kind, x, y, z) => {
    const pos = P(x, y + 3.2, z);
    return part({ name: 'PuntoSparring_' + kind, size: [1, 1, 1], pos, rot: facing(pos, P(x, y + 3.2, z - 20)), transparency: 1, collide: false, color: [255, 255, 255] });
  };
  items.push(enemy('Latido', 0, 0, 56));
  items.push(sign('CartelLatido', 'LATIDO · ataca al ritmo de su corazón · 3 desvíos perfectos seguidos = ¡CONTRATIEMPO!', P(0, 9, 60.6), P(0, 9, 0), [9, 1.6, 0.3]));

  // ---------- C. Abismo ----------
  // Tres pisos con huecos de 8 (un salto corriendo: a 22 studs/s un salto recorre ~11,4) y 16 (salto + Paso
  // en el aire). Tocar el foso devuelve a PuntoRetornoAbismo (GrietaService).
  const C0 = 61, C1 = 121;
  items.push(box('AbismoBordeInicio', [-20, -6, C0], [20, 0, 74], FLOOR, 'Cobblestone'));
  items.push(box('AbismoIsla', [-7, -6, 82], [7, 0, 92], FLOOR, 'Cobblestone'));
  items.push(box('AbismoBordeFinal', [-20, -6, 108], [20, 0, C1], FLOOR, 'Cobblestone'));
  const retorno = P(0, 3.2, 68);
  items.push(part({ name: 'PuntoRetornoAbismo', size: [1, 1, 1], pos: retorno, rot: facing(retorno, P(0, 3.2, 200)), transparency: 1, collide: false, color: [255, 255, 255] }));
  items.push(box('AbismoFoso', [-20, -16, C0], [20, -14, C1], STONE_DARK, 'Rock'));
  items.push(box('AbismoTecho', [-20, 26, C0], [20, 28, C1], STONE_DARK, 'Rock'));
  items.push(...wallX('AbismoParedO', -21, C0, C1, -16, 28), ...wallX('AbismoParedE', 21, C0, C1, -16, 28));
  items.push(...wallZ('AbismoEntrada', C0, -22, 22, -16, 28, [-5, 5, 0, 12]));
  items.push(...wallZ('AbismoSalida', C1, -22, 22, -16, 28, [-6, 6, 0, 12]));
  // Cristales en el foso: lo iluminan desde abajo (se ve la profundidad)
  [[-12, 100], [10, 80], [14, 104], [-4, 70], [6, 96], [-15, 110]].forEach(([x, z], i) => {
    items.push(crystal('CristalFoso' + i, x, -14, z, 3 + (i % 3) * 1.5, [90, 220, 255], i * 37));
  });
  for (const z of [66, 116]) {
    items.push(...torch('AntorchaAbismoO', -20, 6, z, -1), ...torch('AntorchaAbismoE', 20, 6, z, 1));
  }
  items.push(enemy('Acechador', 0, 0, 89));
  items.push(sign('CartelAcechador', 'ACECHADOR · si fallas un golpe pesado cerca de él, te embiste', P(0, 6, 92.2), P(0, 6, 0), [10, 1.6, 0.3]));
  items.push(enemy('Centinela', 0, 0, 113)); // más espacio entre él y la puerta: su golpe (alcance ~10) ya no llega dentro de la sala de ascenso
  items.push(sign('CartelCentinela', 'CENTINELA · coraza al frente · Contrapaso y golpea su espalda', P(0, 14, C1 - 1.2), P(0, 14, 0), [16, 2.4, 0.4]));
  items.push(sign('CartelAbismo', 'salta (8) · luego salto + Paso en el aire (16) · o cruza corriendo por la pared', P(0, 16, C0 + 1.2), P(0, 16, 200), [22, 3, 0.4]));

  // ---------- D. Ascenso ----------
  const D0 = 121, D1 = 153;
  items.push(...shell('Ascenso', -16, 16, D0, D1, 0, 44, 'Slate'));
  items.push(...wallZ('AscensoSalida', D1, -18, 18, -2, 46, [6, 14, 28, 40]));
  items.push(...wallZ('AscensoFondoAlto', D0, -18, 18, 28, 46)); // cierra por encima del techo del Abismo
  // Repisas: 6 → 13 → 20 → 28 (cada una a menos de un salto o un doble salto de la anterior)
  items.push(box('Repisa6', [-14, 0, 126], [-6, 6, 134], STONE, 'Slate'));
  items.push(box('Repisa13', [-14, 11, 138], [-6, 13, 146], STONE, 'Slate'));
  items.push(box('Repisa20', [-2, 18, 142], [6, 20, 150], STONE, 'Slate'));
  items.push(box('Repisa28', [6, 26, 134], [14, 28, 142], STONE, 'Slate'));
  items.push(box('PasarelaSalida', [6, 26, 142], [14, 28, 153], STONE, 'Slate'));
  items.push(crystal('CristalAscenso1', -10, 13, 142, 2.5, [150, 120, 255], 20));
  items.push(crystal('CristalAscenso2', 2, 20, 146, 2.5, [150, 120, 255], 60));
  items.push(crystal('CristalAscenso3', 10, 28, 138, 2.5, [150, 120, 255], 110));
  for (const [z, y] of [[128, 8], [146, 22]]) {
    items.push(...torch('AntorchaAscensoO', -16, y, z, -1), ...torch('AntorchaAscensoE', 16, y, z, 1));
  }
  items.push(enemy('Gemelo', -4, 0, 132), enemy('Gemelo', 6, 0, 128));
  // Carteles en la pared, a los lados de la puerta (dentro del marco tapaban la vista al entrar)
  items.push(sign('CartelGemelos', 'GEMELOS · una sola vida · un desvío perfecto refleja el golpe al otro', P(-12, 6, D0 + 1.2), P(-12, 6, 300), [10, 2.4, 0.4]));
  items.push(sign('CartelAscenso', 'sube: salto · doble salto', P(12, 6, D0 + 1.2), P(12, 6, 300), [9, 2.4, 0.4]));

  // ---------- E. Sala del Guardián ----------
  const E0 = 153, E1 = 189, EY = 28;
  items.push(...shell('Guardian', -8, 28, E0, E1, EY, 22, 'Marble'));
  items.push(...wallZ('GuardianFondo', E1, -10, 30, EY - 2, EY + 24));
  items.push(...wallZ('GuardianEntrada', E0, -10, 30, EY - 2, EY + 24, [6, 14, EY, EY + 12]));
  for (const [x, z] of [[-3, 158], [23, 158], [-3, 184], [23, 184]]) {
    items.push(pillar('ColumnaGuardian', x, z, EY, 22));
  }
  // Círculo del duelo (marca, no colisiona)
  for (let k = 0; k < 16; k++) {
    const a = (k / 16) * Math.PI * 2;
    items.push(
      part({
        name: 'Circulo',
        size: [2.2, 0.06, 0.4],
        pos: P(10 + Math.cos(a) * 10, EY + 0.03, 172 + Math.sin(a) * 10),
        rot: rotY(-(a * 180) / Math.PI + 90),
        color: [170, 90, 255],
        material: 'Neon',
        collide: false,
      }),
    );
  }
  items.push(crystal('CristalGuardian1', -5, EY, 186, 6, [170, 90, 255], 15), crystal('CristalGuardian2', 25, EY, 186, 6, [170, 90, 255], 75));
  for (const z of [160, 176]) {
    items.push(...torch('AntorchaGuardianO', -8, EY + 7, z, -1), ...torch('AntorchaGuardianE', 28, EY + 7, z, 1));
  }
  items.push(sign('CartelGuardian', 'GUARDIÁN DE LA GRIETA', P(10, EY + 15, E1 - 1.2), P(10, EY + 15, 0), [16, 3, 0.4]));
  // El compañero de combate aparece aquí (SparringService busca todas las marcas PuntoSparring)
  const guardianPos = P(10, EY + 3.2, 176);
  items.push(part({ name: 'PuntoSparring', size: [1, 1, 1], pos: guardianPos, rot: facing(guardianPos, P(10, EY + 3.2, E0)), transparency: 1, collide: false, color: [255, 255, 255] }));

  return folder('Grieta', items);
}

// Iluminación del lugar de desarrollo: noche, atmósfera densa, brillo y color frío.
// (El lugar de pruebas conserva la luz de día del laboratorio.)
export function dungeonLighting() {
  return {
    props: [
      ['token', 'Technology', 4], // Enum.Technology.Future = 4: luces puntuales con sombras (antorchas)
      ['bool', 'GlobalShadows', true],
      ['float', 'ClockTime', 0.5],
      ['float', 'Brightness', 1],
      ['color3', 'Ambient', [0.035, 0.035, 0.05]],
      ['color3', 'OutdoorAmbient', [0.2, 0.2, 0.26]],
      ['float', 'EnvironmentDiffuseScale', 0.4],
      ['float', 'EnvironmentSpecularScale', 0.6],
    ],
    children: [
      {
        className: 'Atmosphere',
        name: 'Atmosfera',
        props: [
          ['float', 'Density', 0.32],
          ['float', 'Offset', 0.05],
          ['color3', 'Color', [0.22, 0.23, 0.28]],
          ['color3', 'Decay', [0.1, 0.1, 0.13]],
          ['float', 'Glare', 0],
          ['float', 'Haze', 1.2],
        ],
        children: [],
      },
      {
        className: 'BloomEffect',
        name: 'Brillo',
        props: [
          ['float', 'Intensity', 0.9],
          ['float', 'Size', 28],
          ['float', 'Threshold', 0.92],
        ],
        children: [],
      },
      {
        className: 'ColorCorrectionEffect',
        name: 'Color',
        props: [
          ['float', 'Brightness', 0.02],
          ['float', 'Contrast', 0.14],
          ['float', 'Saturation', -0.05],
          ['color3', 'TintColor', [1, 0.97, 0.94]],
        ],
        children: [],
      },
    ],
  };
}
