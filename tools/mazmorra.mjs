// La Grieta (muestra de ambiente): primera mazmorra jugable, SOLO en el lugar de desarrollo.
// No es el mundo definitivo (Alba, el Faro y las Grietas finales llegan en la Fase 11): sirve para ver
// cómo luce y se siente el movimiento y el combate en un lugar con ambiente.
//
// Está bajo tierra (Y = -200), cerrada por todos lados, así que su luz es la de sus antorchas y cristales.
// Recorrido, con medidas que salen del movimiento real (salto 8,5 · doble salto 15,5 · Paso 14):
//   A. Umbral (aparición) → B. pasillo → C. Abismo: salto de 8 y salto + Paso de 16; caer al foso te
//   devuelve al borde de inicio (GrietaService) → D. Ascenso: repisas de 6, 13, 20 y 28 (salto y doble salto) →
//   E. Sala del Guardián: el compañero de combate espera en el centro.

import { part, sign, folder, rotY, rotYXZ, facing } from './mapa.mjs';

const O = [0, -200, 0]; // origen de la mazmorra
const P = (x, y, z) => [O[0] + x, O[1] + y, O[2] + z];

// Paleta: piedra con un toque violeta (la Grieta "resuena"), suelo cálido, acentos de Eco en los cristales
const STONE = [88, 82, 96];
const STONE_DARK = [56, 50, 64];
const FLOOR = [108, 98, 88];
const WOOD = [96, 62, 38];
const TRIM = [44, 40, 52];
const EMBER = [255, 150, 60];

// Variación de tono pieza a pieza (determinista: el mismo mapa en cada construcción). Sin ella, las paredes de
// un solo color se ven planas.
let seed = 7;
function rand() {
  seed = (seed * 1103515245 + 12345) % 2147483648;
  return seed / 2147483648;
}
function jitter([r, g, b], amount = 7) {
  const d = (rand() * 2 - 1) * amount;
  const c = (v) => Math.max(0, Math.min(255, Math.round(v + d)));
  return [c(r), c(g), c(b)];
}

// Caja por esquinas (más fácil de leer que centro + tamaño)
function box(name, [x0, y0, z0], [x1, y1, z1], color = STONE, material = 'Slate', extra = {}) {
  const base = color === STONE || color === STONE_DARK || color === FLOOR ? jitter(color) : color;
  return part({
    name,
    size: [Math.abs(x1 - x0), Math.abs(y1 - y0), Math.abs(z1 - z0)],
    pos: P((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
    color: base,
    material,
    ...extra,
  });
}

// Zócalo y cornisa a lo largo de una pared lateral (solo se ven: no chocan, así no cambian el movimiento)
function trimsX(name, x, side, z0, z1, y0, height) {
  const inner = x + side * 1.2; // cara interior de la pared
  return [
    box(name + 'Zocalo', [inner - 0.3, y0, z0], [inner + 0.3, y0 + 1.4, z1], TRIM, 'Basalt', { collide: false }),
    box(name + 'Cornisa', [inner - 0.4, y0 + height - 1.6, z0], [inner + 0.4, y0 + height - 0.8, z1], TRIM, 'Granite', { collide: false }),
  ];
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
    ...trimsX(name + 'BordeO', x0 - 1, 1, z0, z1, y0, height),
    ...trimsX(name + 'BordeE', x1 + 1, -1, z0, z1, y0, height),
  ];
}

// Racimo de cristales del Eco: 3-4 puntas inclinadas, una luz de color. Sin colisión.
function crystalCluster(name, x, y, z, color, scale = 1) {
  const items = [];
  const tips = [
    [0, 0, 4.2, 0, 0],
    [0.9, 0.4, 2.8, 24, 0],
    [-0.8, 0.6, 2.4, -20, 14],
    [0.2, -0.9, 1.8, 10, -26],
  ];
  tips.forEach(([dx, dz, h, tiltX, tiltZ], i) => {
    const height = h * scale;
    items.push(
      part({
        name: name + 'Punta' + i,
        size: [0.9 * scale, height, 0.9 * scale],
        pos: P(x + dx * scale, y + height / 2 - 0.2, z + dz * scale),
        rot: rotYXZ(rand() * 90, tiltX, tiltZ),
        color: i === 0 ? color : color.map((c) => Math.round(c * 0.8)),
        material: 'Neon',
        collide: false,
        transparency: 0.12,
        children:
          i === 0
            ? [
                {
                  className: 'PointLight',
                  name: 'Luz',
                  props: [
                    ['float', 'Brightness', 2.2],
                    ['float', 'Range', 18 * Math.min(scale, 1.4)],
                    ['color3', 'Color', color.map((c) => c / 255)],
                    ['bool', 'Shadows', false],
                  ],
                  children: [],
                },
              ]
            : [],
      }),
    );
  });
  // Base de roca oscura de la que salen
  items.push(part({ name: name + 'Base', size: [2.6 * scale, 0.8 * scale, 2.4 * scale], pos: P(x, y + 0.2, z), rot: rotYXZ(rand() * 90, 4, -3), color: jitter(TRIM, 5), material: 'Basalt', collide: false }));
  return items;
}

// Brasero: cuenco de metal sobre un pie, con fuego y luz cálida
function brazier(name, x, y, z) {
  return [
    part({ name: name + 'Pie', size: [0.8, 3, 0.8], pos: P(x, y + 1.5, z), color: [40, 36, 40], material: 'CorrodedMetal', collide: false }),
    part({
      name: name + 'Cuenco',
      size: [1.2, 2.6, 2.6],
      pos: P(x, y + 3.4, z),
      rot: { x: [0, 1, 0], y: [-1, 0, 0], z: [0, 0, 1] }, // cilindro de pie
      color: [52, 46, 50],
      material: 'CorrodedMetal',
      collide: false,
      extra: [['token', 'shape', 2]],
    }),
    part({
      name: name + 'Brasas',
      size: [0.6, 2, 2],
      pos: P(x, y + 4.1, z),
      rot: { x: [0, 1, 0], y: [-1, 0, 0], z: [0, 0, 1] }, // disco tendido dentro del cuenco
      color: EMBER,
      material: 'Neon',
      collide: false,
      children: [
        {
          className: 'PointLight',
          name: 'Luz',
          props: [
            ['float', 'Brightness', 2.6],
            ['float', 'Range', 24],
            ['color3', 'Color', [1, 0.6, 0.3]],
            ['bool', 'Shadows', true],
          ],
          children: [],
        },
        {
          className: 'Fire',
          name: 'Fuego',
          props: [
            ['float', 'size_xml', 3.5],
            ['float', 'heat_xml', 9],
            ['color3', 'Color', [1, 0.55, 0.2]],
            ['color3', 'SecondaryColor', [0.9, 0.22, 0.05]],
          ],
          children: [],
        },
      ],
      extra: [['token', 'shape', 2]],
    }),
  ];
}

// Estandarte colgado de una pared lateral (side: +1 pared este, -1 oeste): tela de color con una franja que brilla
function banner(name, x, y, z, side, color) {
  const inner = x - side * 0.25;
  return [
    part({ name: name + 'Barra', size: [0.3, 0.3, 4.2], pos: P(inner, y + 3.2, z), color: [40, 36, 40], material: 'Metal', collide: false }),
    part({ name: name + 'Tela', size: [0.15, 6, 3.4], pos: P(inner - side * 0.05, y, z), color, material: 'Fabric', collide: false }),
    part({ name: name + 'Franja', size: [0.18, 5.2, 0.35], pos: P(inner - side * 0.08, y, z), color: color.map((c) => Math.min(255, c + 90)), material: 'Neon', collide: false, transparency: 0.25 }),
  ];
}

// Escombros: piedras sueltas junto a las paredes (no chocan)
function rubble(name, x0, x1, z0, z1, y, count) {
  const items = [];
  for (let i = 0; i < count; i++) {
    const s = 0.5 + rand() * 1.3;
    items.push(part({ name: name + i, size: [s, s * (0.5 + rand() * 0.6), s * (0.7 + rand() * 0.6)], pos: P(x0 + rand() * (x1 - x0), y + s * 0.25, z0 + rand() * (z1 - z0)), rot: rotYXZ(rand() * 360, rand() * 30, rand() * 30), color: jitter(STONE_DARK, 10), material: rand() < 0.5 ? 'Rock' : 'Basalt', collide: false }));
  }
  return items;
}

// Runas: un círculo de trazos que brillan en el suelo (marca, no colisiona)
function runeCircle(name, cx, y, cz, radius, color, count = 16, transparency = 0) {
  const items = [];
  for (let k = 0; k < count; k++) {
    const a = (k / count) * Math.PI * 2;
    items.push(part({ name, size: [(Math.PI * 2 * radius) / count * 0.7, 0.06, 0.32], pos: P(cx + Math.cos(a) * radius, y + 0.03, cz + Math.sin(a) * radius), rot: rotY(-(a * 180) / Math.PI + 90), color, material: 'Neon', collide: false, transparency }));
  }
  return items;
}

// Volumen de partículas de ambiente: el cliente (AmbienteController) le pone motas que flotan del color de la
// pieza. `kind`: 'Motas' (polvo de luz) o 'Niebla' (bruma baja).
function ambience(kind, [x0, y0, z0], [x1, y1, z1], color) {
  return part({ name: kind, size: [Math.abs(x1 - x0), Math.abs(y1 - y0), Math.abs(z1 - z0)], pos: P((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, transparency: 1, collide: false, extra: [['bool', 'CanQuery', false], ['bool', 'CanTouch', false]] });
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
            ['float', 'Brightness', 2.6],
            ['float', 'Range', 23],
            ['color3', 'Color', [1, 0.6, 0.3]],
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
// Punto de enganche (Gancho, tecla E): orbe brillante sin colisión. El cliente los busca por su nombre.
function hook(x, y, z) {
  return part({ name: 'PuntoGancho', size: [1.6, 1.6, 1.6], pos: P(x, y, z), color: [120, 255, 230], material: 'Neon', collide: false, extra: [['token', 'shape', 0]] });
}

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
  // Muñecos de práctica junto a la entrada: para probar las habilidades nada más llegar (no atacan)
  for (const [x, name] of [[-6, 'PuntoMunecoGrieta1'], [6, 'PuntoMunecoGrieta2']]) {
    const pos = P(x, 3.2, 19);
    items.push(part({ name, size: [1, 1, 1], pos, rot: facing(pos, P(0, 3.2, 19)), transparency: 1, collide: false, color: [255, 255, 255] }));
  }
  items.push(sign('CartelMunecos', 'MUÑECOS · prueba Z X C V · 1-5 cambia de Eco · Q espada', P(0, 10, 39.6), P(0, 10, 0), [18, 2.4, 0.4]));
  for (const z of [12, 24]) {
    items.push(...banner('EstandarteO', -12, 10, z, -1, [92, 48, 140]), ...banner('EstandarteE', 12, 10, z, 1, [36, 110, 120]));
  }
  items.push(...brazier('BraseroUmbral1', -8, 0, 37), ...brazier('BraseroUmbral2', 8, 0, 37));
  items.push(...crystalCluster('CristalesUmbral1', -10.2, 0, 1.6, [150, 110, 255], 0.9), ...crystalCluster('CristalesUmbral2', 10.2, 0, 1.6, [90, 230, 255], 0.9));
  items.push(...runeCircle('RunaAparicion', 0, 0.5, 6, 5.2, [170, 130, 255], 20, 0.15));
  items.push(...rubble('EscombroUmbral', -11, -9.5, 3, 37, 0, 7), ...rubble('EscombroUmbralE', 9.5, 11, 3, 37, 0, 7));
  items.push(ambience('Motas', [-11, 1, 1], [11, 16, 39], [255, 200, 140]));

  // ---------- B. Pasillo ----------
  items.push(box('PasilloPiso', [-5, -8, 41], [5, 0, 61], FLOOR, 'Cobblestone'));
  items.push(box('PasilloTecho', [-5, 12, 41], [5, 14, 61], STONE_DARK, 'Rock'));
  items.push(...wallX('PasilloParedO', -6, 41, 61, -2, 14), ...wallX('PasilloParedE', 6, 41, 61, -2, 14));
  items.push(...torch('AntorchaPasillo', -5, 6, 51, -1), ...torch('AntorchaPasilloE', 5, 6, 45, 1));
  for (const x of [-4.4, 4.4]) {
    items.push(part({ name: 'GuiaLuz', size: [0.25, 0.06, 19.6], pos: P(x, 0.03, 51), color: [90, 220, 255], material: 'Neon', collide: false, transparency: 0.35 }));
  }
  items.push(ambience('Motas', [-4.5, 1, 42], [4.5, 11, 60], [140, 220, 255]));
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
  items.push(...crystalCluster('CristalesBorde1', -17.5, 0, 63.5, [90, 220, 255], 1.1), ...crystalCluster('CristalesBorde2', 17.5, 0, 118.5, [90, 220, 255], 1.1));
  items.push(...crystalCluster('CristalesIsla', 5.5, 0, 90.5, [120, 255, 230], 0.7));
  items.push(ambience('Niebla', [-19, -14, 75], [19, -7, 107], [80, 170, 255]));
  items.push(ambience('Motas', [-19, 0, 62], [19, 24, 120], [120, 210, 255]));
  items.push(...rubble('EscombroAbismo', -19.5, -15, 62, 73, 0, 6), ...rubble('EscombroAbismoE', 15, 19.5, 109, 120, 0, 6));
  items.push(enemy('Acechador', 0, 0, 89));
  items.push(sign('CartelAcechador', 'ACECHADOR · si fallas un golpe pesado cerca de él, te embiste', P(0, 6, 92.2), P(0, 6, 0), [10, 1.6, 0.3]));
  items.push(enemy('Centinela', 0, 0, 113)); // más espacio entre él y la puerta: su golpe (alcance ~10) ya no llega dentro de la sala de ascenso
  items.push(sign('CartelCentinela', 'CENTINELA · coraza al frente · Contrapaso y golpea su espalda', P(0, 14, C1 - 1.2), P(0, 14, 0), [16, 2.4, 0.4]));
  // Gancho (E): puntos de enganche sobre los dos saltos del abismo
  items.push(hook(0, 13, 78), hook(0, 15, 100));
  items.push(sign('CartelAbismo', 'salta (8) · salto + Paso en el aire (16) · corre por la pared · o E: gancho a los orbes', P(0, 16, C0 + 1.2), P(0, 16, 200), [22, 3, 0.4]));

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
  items.push(...banner('EstandarteAscensoO', -16, 30, 132, -1, [92, 48, 140]), ...banner('EstandarteAscensoE', 16, 30, 132, 1, [92, 48, 140]));
  items.push(...crystalCluster('CristalesAscenso', 13, 0, 124, [150, 110, 255], 1));
  items.push(ambience('Motas', [-15, 1, 122], [15, 42, 152], [190, 150, 255]));
  // Gancho (E): atajos hacia las repisas altas
  items.push(hook(-10, 22, 136), hook(10, 36, 140));
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
  items.push(...runeCircle('CirculoInterior', 10, EY, 172, 6.5, [255, 90, 200], 12, 0.2));
  for (let k = 0; k < 8; k++) {
    const a = (k / 8) * Math.PI * 2;
    items.push(part({ name: 'RadioRuna', size: [3, 0.05, 0.22], pos: P(10 + Math.cos(a) * 8.3, EY + 0.03, 172 + Math.sin(a) * 8.3), rot: rotY(-(a * 180) / Math.PI), color: [200, 120, 255], material: 'Neon', collide: false, transparency: 0.3 }));
  }
  items.push(...brazier('BraseroGuardian1', 1, EY, 157.5), ...brazier('BraseroGuardian2', 19, EY, 157.5));
  items.push(...crystalCluster('CristalesGuardian1', -5.5, EY, 157, [255, 90, 200], 1.2), ...crystalCluster('CristalesGuardian2', 25.5, EY, 157, [255, 90, 200], 1.2));
  items.push(ambience('Motas', [-7, EY + 1, 154], [27, EY + 20, 188], [255, 150, 230]));
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
      ['float', 'Brightness', 2],
      ['color3', 'Ambient', [0.1, 0.09, 0.13]],
      ['color3', 'OutdoorAmbient', [0.26, 0.24, 0.32]],
      ['float', 'EnvironmentDiffuseScale', 0.6],
      ['float', 'EnvironmentSpecularScale', 0.9],
    ],
    children: [
      {
        className: 'Atmosphere',
        name: 'Atmosfera',
        props: [
          ['float', 'Density', 0.27],
          ['float', 'Offset', 0.05],
          ['color3', 'Color', [0.3, 0.26, 0.4]],
          ['color3', 'Decay', [0.14, 0.1, 0.2]],
          ['float', 'Glare', 0.15],
          ['float', 'Haze', 1.6],
        ],
        children: [],
      },
      {
        className: 'BloomEffect',
        name: 'Brillo',
        props: [
          ['float', 'Intensity', 1.1],
          ['float', 'Size', 32],
          ['float', 'Threshold', 0.85],
        ],
        children: [],
      },
      {
        className: 'ColorCorrectionEffect',
        name: 'Color',
        props: [
          ['float', 'Brightness', 0.05],
          ['float', 'Contrast', 0.18],
          ['float', 'Saturation', 0.22],
          ['color3', 'TintColor', [1, 0.96, 1]],
        ],
        children: [],
      },
    ],
  };
}
