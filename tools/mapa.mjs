// Mapa del laboratorio de movimiento (Fase 1). Todo en studs; el suelo está en Y = 0.
// Vista desde arriba: X a la derecha, Z hacia adelante. El jugador aparece en el origen mirando a +Z.
//   +Z: pista de Paso con marcas cada 10 studs      -Z: brechas para saltar y dar Pasos
//   -X: slalom de pilares (cambios de dirección)     +X: pilares de altura de salto
//   +X+Z: rampas y escalera                          -X+Z: túnel y muro (cámara y choques)

const MATERIAL = { Plastic: 256, SmoothPlastic: 272, Neon: 288, Slate: 800, Concrete: 816, Metal: 1088 };
const FACE = { Right: 0, Top: 1, Back: 2, Left: 3, Bottom: 4, Front: 5 };
const IDENT = { x: [1, 0, 0], y: [0, 1, 0], z: [0, 0, 1] };

export function rotY(deg) {
  const r = (deg * Math.PI) / 180;
  const c = Math.round(Math.cos(r) * 1e6) / 1e6;
  const s = Math.round(Math.sin(r) * 1e6) / 1e6;
  return { x: [c, 0, -s], y: [0, 1, 0], z: [s, 0, c] };
}

// Orientación cuya cara Front (-Z local) mira hacia `target`, solo girando en Y.
function facing(pos, target) {
  let fx = target[0] - pos[0];
  let fz = target[2] - pos[2];
  const len = Math.hypot(fx, fz) || 1;
  fx /= len;
  fz /= len;
  return { x: [-fz, 0, fx], y: [0, 1, 0], z: [-fx, 0, -fz] };
}

function part({ name, size, pos, rot = IDENT, color = [120, 125, 135], material = 'SmoothPlastic', className = 'Part', collide = true, transparency = 0, children = [], extra = [] }) {
  return {
    className,
    name,
    props: [
      ['bool', 'Anchored', true],
      ['bool', 'CanCollide', collide],
      ['vector3', 'size', size],
      ['cframe', 'CFrame', { pos, rot }],
      ['color3uint8', 'Color3uint8', color],
      ['token', 'Material', MATERIAL[material]],
      ['float', 'Transparency', transparency],
      ['token', 'TopSurface', 0],
      ['token', 'BottomSurface', 0],
      ...extra,
    ],
    children,
  };
}

function surfaceText(text, face = 'Front', color = [1, 1, 1]) {
  return {
    className: 'SurfaceGui',
    name: 'Texto',
    props: [
      ['token', 'Face', FACE[face]],
      ['float', 'LightInfluence', 0],
      ['token', 'SizingMode', 1],
      ['float', 'PixelsPerStud', 40],
    ],
    children: [
      {
        className: 'TextLabel',
        name: 'Etiqueta',
        props: [
          ['udim2', 'Size', [1, 0, 1, 0]],
          ['float', 'BackgroundTransparency', 1],
          ['string', 'Text', text],
          ['bool', 'TextScaled', true],
          ['bool', 'TextWrapped', true],
          ['color3', 'TextColor3', color],
          ['font', 'FontFace', { family: 'rbxasset://fonts/families/GothamSSm.json', weight: 700, style: 'Normal' }],
        ],
        children: [],
      },
    ],
  };
}

function sign(name, text, pos, lookAt = [0, pos[1], 0], size = [16, 4, 0.4]) {
  return part({ name, size, pos, rot: facing(pos, lookAt), color: [16, 20, 34], collide: false, children: [surfaceText(text)] });
}

function folder(name, children) {
  return { className: 'Folder', name, props: [], children };
}

export function buildMovementLab() {
  const zones = [];

  // Suelo y punto de aparición
  zones.push(part({ name: 'Suelo', size: [600, 2, 600], pos: [0, -1, 0], color: [74, 80, 94], material: 'Concrete' }));
  zones.push(
    part({
      name: 'Aparicion',
      className: 'SpawnLocation',
      size: [12, 1, 12],
      pos: [0, 0.5, 0],
      rot: rotY(180),
      color: [40, 70, 130],
      extra: [
        ['bool', 'Neutral', true],
        ['int', 'Duration', 0],
      ],
    }),
  );

  // Pista de Paso: marcas cada 10 studs para medir distancias
  const pista = [part({ name: 'Franja', size: [12, 0.02, 200], pos: [0, 0.01, 120], color: [34, 48, 82], collide: false })];
  for (let k = 0; k <= 20; k++) {
    const z = 20 + k * 10;
    const fuerte = k % 5 === 0;
    pista.push(part({ name: `Marca${k * 10}`, size: [12, 0.04, fuerte ? 0.6 : 0.3], pos: [0, 0.03, z], color: fuerte ? [255, 210, 70] : [220, 230, 255], material: 'Neon', collide: false }));
    pista.push(sign(`Cartel${k * 10}`, String(k * 10), [8, 1.5, z], [0, 1.5, z], [3, 2, 0.3]));
  }
  pista.push(sign('Titulo', 'PISTA DE PASO · marcas cada 10 studs', [0, 9, 18]));
  zones.push(folder('PistaDePaso', pista));

  // Slalom: pilares alternados para cambiar de dirección a toda velocidad
  const slalom = [];
  for (let k = 0; k < 8; k++) {
    slalom.push(part({ name: `Pilar${k + 1}`, size: [3, 10, 3], pos: [-30 - k * 12, 5, k % 2 ? 5 : -5], color: [230, 120, 50] }));
  }
  slalom.push(sign('Titulo', 'SLALOM · cambios de dirección', [-28, 12, -16]));
  zones.push(folder('Slalom', slalom));

  // Pilares de altura: un salto normal llega a ~8, el doble salto a ~15
  const alturas = [];
  [4, 6, 8, 10, 12, 14, 16, 18].forEach((h, k) => {
    const shade = 90 + k * 18;
    alturas.push(part({ name: `Altura${h}`, size: [8, h, 8], pos: [30 + k * 14, h / 2, 0], color: [60, shade, 120], children: [surfaceText(String(h), 'Left')] }));
  });
  alturas.push(sign('Titulo', 'ALTURA DE SALTO · 1 salto ≈ 8 · doble ≈ 15', [28, 22, -16]));
  zones.push(folder('AlturaDeSalto', alturas));

  // Brechas: plataformas a 6 de altura separadas por huecos cada vez más grandes
  const brechas = [];
  brechas.push(part({ name: 'Rampa', className: 'WedgePart', size: [10, 6, 14], pos: [0, 3, -19], rot: rotY(180), color: [110, 80, 160] }));
  brechas.push(part({ name: 'Inicio', size: [10, 6, 12], pos: [0, 3, -32], color: [110, 80, 160] }));
  let edge = -38;
  [10, 16, 22, 28].forEach((gap, k) => {
    const start = edge - gap;
    brechas.push(part({ name: `Plataforma${k + 1}`, size: [10, 6, 12], pos: [0, 3, start - 6], color: [130 + k * 25, 90, 180], children: [surfaceText(`Brecha ${gap}`, 'Back')] }));
    edge = start - 12;
  });
  brechas.push(sign('Titulo', 'BRECHAS · salto, Paso y doble salto', [-12, 12, -40], [0, 12, 0]));
  zones.push(folder('Brechas', brechas));

  // Rampas de 20°, 35° y 50° y una escalera
  const rampas = [];
  [20, 35, 50].forEach((deg, k) => {
    const x = 40 + k * 16;
    const run = Math.round((6 / Math.tan((deg * Math.PI) / 180)) * 100) / 100;
    rampas.push(part({ name: `Rampa${deg}`, className: 'WedgePart', size: [10, 6, run], pos: [x, 3, 40 + run / 2], color: [70, 140, 150] }));
    rampas.push(part({ name: `Cima${deg}`, size: [10, 6, 10], pos: [x, 3, 40 + run + 5], color: [60, 120, 130] }));
    rampas.push(sign(`Cartel${deg}`, `${deg}°`, [x, 8, 37], [x, 8, 0], [6, 2.5, 0.3]));
  });
  for (let i = 1; i <= 8; i++) {
    rampas.push(part({ name: `Escalon${i}`, size: [10, i, 2], pos: [92, i / 2, 40 + 2 * i - 1], color: [80, 110 + i * 8, 140] }));
  }
  rampas.push(part({ name: 'CimaEscalera', size: [10, 8, 10], pos: [92, 4, 61], color: [70, 110, 140] }));
  rampas.push(sign('Titulo', 'RAMPAS Y ESCALERA', [66, 14, 30]));
  zones.push(folder('RampasYEscalera', rampas));

  // Túnel y muro: para probar la cámara en espacios cerrados y los choques
  const cerrado = [
    part({ name: 'ParedTunelA', size: [2, 6, 30], pos: [-54, 3, 30], color: [90, 96, 112] }),
    part({ name: 'ParedTunelB', size: [2, 6, 30], pos: [-66, 3, 30], color: [90, 96, 112] }),
    part({ name: 'TechoTunel', size: [14, 1, 30], pos: [-60, 6.5, 30], color: [70, 76, 92] }),
    part({ name: 'Muro', size: [40, 30, 2], pos: [-60, 15, 70], color: [56, 64, 86] }),
    sign('Titulo', 'TÚNEL Y MURO · cámara y choques', [-46, 10, 12]),
  ];
  zones.push(folder('TunelYMuro', cerrado));

  // Dojo (Fase 2): tatami con muñecos de práctica. Las marcas PuntoMuneco* son invisibles; DummyService
  // pone un muñeco en cada una, mirando hacia +Z (hacia quien llega desde el origen).
  const dojo = [
    part({ name: 'Tatami', size: [44, 0.04, 44], pos: [80, 0.02, -70], color: [150, 112, 70], material: 'Plastic', collide: false }),
    part({ name: 'BordeNorte', size: [44, 0.06, 0.6], pos: [80, 0.03, -48], color: [200, 60, 50], material: 'Neon', collide: false }),
    part({ name: 'BordeSur', size: [44, 0.06, 0.6], pos: [80, 0.03, -92], color: [200, 60, 50], material: 'Neon', collide: false }),
    part({ name: 'BordeEste', size: [0.6, 0.06, 44], pos: [102, 0.03, -70], color: [200, 60, 50], material: 'Neon', collide: false }),
    part({ name: 'BordeOeste', size: [0.6, 0.06, 44], pos: [58, 0.03, -70], color: [200, 60, 50], material: 'Neon', collide: false }),
    sign('Titulo', 'DOJO · clic: combo · mantener: golpe fuerte · F: guardia', [80, 10, -46], [80, 10, 0], [26, 4, 0.4]),
  ];
  const marker = (name, pos) => part({ name, size: [1, 1, 1], pos, rot: rotY(180), transparency: 1, collide: false, color: [255, 255, 255] });
  dojo.push(marker('PuntoMuneco1', [68, 3.2, -70]));
  dojo.push(marker('PuntoMuneco2', [80, 3.2, -70]));
  dojo.push(marker('PuntoMuneco3', [92, 3.2, -70]));
  dojo.push(marker('PuntoMunecoAguante', [80, 3.2, -86]));
  zones.push(folder('Dojo', dojo));

  // Ring (Fase 3): el compañero de combate ataca para practicar desvío, guardia, Contrapaso y saltos.
  // Lejos del Dojo para que no ataque a quien practica con los muñecos.
  const ring = [
    part({ name: 'Lona', size: [32, 0.04, 32], pos: [-60, 0.02, -80], color: [60, 66, 90], material: 'Plastic', collide: false }),
    part({ name: 'BordeNorte', size: [32, 0.06, 0.6], pos: [-60, 0.03, -64], color: [90, 150, 255], material: 'Neon', collide: false }),
    part({ name: 'BordeSur', size: [32, 0.06, 0.6], pos: [-60, 0.03, -96], color: [90, 150, 255], material: 'Neon', collide: false }),
    part({ name: 'BordeEste', size: [0.6, 0.06, 32], pos: [-44, 0.03, -80], color: [90, 150, 255], material: 'Neon', collide: false }),
    part({ name: 'BordeOeste', size: [0.6, 0.06, 32], pos: [-76, 0.03, -80], color: [90, 150, 255], material: 'Neon', collide: false }),
    sign('Titulo', 'RING · F a tiempo: desvío · mantener: guardia · Paso de lado: Contrapaso', [-60, 10, -62], [-60, 10, 0], [30, 4, 0.4]),
    marker('PuntoSparring', [-60, 3.2, -84]),
  ];
  zones.push(folder('Ring', ring));

  return [folder('Maps', [folder('MovementLab', zones)])];
}
