// Construye build/UMBRAL-Desarrollo.rbxlx a partir de src/ y del mapa de tools/mapa.mjs.
// Uso:  node tools/construir.mjs                      → lugar de desarrollo
//       node tools/construir.mjs --pruebas            → además build/UMBRAL-Pruebas.rbxlx (con tests/)
//       node tools/construir.mjs --instalar-plugin    → además instala el plugin de pruebas en Studio
//
// Sigue las convenciones de Rojo, así el proyecto se puede pasar a Rojo más adelante sin mover archivos:
//   *.server.luau → Script · *.client.luau → LocalScript · *.luau → ModuleScript · carpeta → Folder
//   src/shared → ReplicatedStorage.Shared · src/server → ServerScriptService · src/client → StarterPlayerScripts

import { copyFileSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildMovementLab } from './mapa.mjs';
import { buildDungeon, dungeonLighting } from './mazmorra.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SRC = join(ROOT, 'src');
const OUT = join(ROOT, 'build', 'UMBRAL-Desarrollo.rbxlx');

// ---------- Lectura de la configuración compartida ----------
const configSource = readFileSync(join(SRC, 'shared', 'Config', 'MovementConfig.luau'), 'utf8');
function configNumber(key) {
  const m = configSource.match(new RegExp(`\\b${key}\\s*=\\s*(-?[\\d.]+)`));
  if (!m) throw new Error(`MovementConfig.luau no define ${key}`);
  return Number(m[1]);
}

// ---------- Serialización XML ----------
let refCounter = 0;
const nextRef = () => `RBX${(++refCounter).toString(16).toUpperCase().padStart(8, '0')}`;
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const cdata = (s) => '<![CDATA[' + s.split(']]>').join(']]]]><![CDATA[>') + ']]>';
const num = (n) => {
  if (!Number.isFinite(n)) throw new Error(`Número inválido: ${n}`);
  return String(Math.round(n * 1e6) / 1e6);
};

const SERIALIZE = {
  string: (n, v) => `<string name="${n}">${esc(v)}</string>`,
  bool: (n, v) => `<bool name="${n}">${v ? 'true' : 'false'}</bool>`,
  float: (n, v) => `<float name="${n}">${num(v)}</float>`,
  int: (n, v) => `<int name="${n}">${Math.trunc(v)}</int>`,
  token: (n, v) => `<token name="${n}">${Math.trunc(v)}</token>`,
  vector3: (n, [x, y, z]) => `<Vector3 name="${n}"><X>${num(x)}</X><Y>${num(y)}</Y><Z>${num(z)}</Z></Vector3>`,
  color3: (n, [r, g, b]) => `<Color3 name="${n}"><R>${num(r)}</R><G>${num(g)}</G><B>${num(b)}</B></Color3>`,
  color3uint8: (n, [r, g, b]) => `<Color3uint8 name="${n}">${4278190080 + (r << 16) + (g << 8) + b}</Color3uint8>`,
  udim2: (n, [xs, xo, ys, yo]) => `<UDim2 name="${n}"><XS>${num(xs)}</XS><XO>${Math.trunc(xo)}</XO><YS>${num(ys)}</YS><YO>${Math.trunc(yo)}</YO></UDim2>`,
  font: (n, { family, weight, style }) => `<Font name="${n}"><Family><url>${esc(family)}</url></Family><Weight>${weight}</Weight><Style>${style}</Style></Font>`,
  source: (n, v) => `<ProtectedString name="${n}">${cdata(v)}</ProtectedString>`,
  cframe: (n, { pos, rot }) => {
    const [px, py, pz] = pos;
    const { x, y, z } = rot; // columnas: RightVector, UpVector, -LookVector
    const r = [x[0], y[0], z[0], x[1], y[1], z[1], x[2], y[2], z[2]];
    const names = ['R00', 'R01', 'R02', 'R10', 'R11', 'R12', 'R20', 'R21', 'R22'];
    return `<CoordinateFrame name="${n}"><X>${num(px)}</X><Y>${num(py)}</Y><Z>${num(pz)}</Z>${names.map((k, i) => `<${k}>${num(r[i])}</${k}>`).join('')}</CoordinateFrame>`;
  },
};

function serialize(inst, depth = 0) {
  const pad = '  '.repeat(depth);
  const props = [SERIALIZE.string('Name', inst.name), ...inst.props.map(([type, name, value]) => {
    const fn = SERIALIZE[type];
    if (!fn) throw new Error(`Tipo de propiedad desconocido: ${type}`);
    return fn(name, value);
  })].join('');
  const children = (inst.children || []).map((c) => serialize(c, depth + 1)).join('\n');
  return `${pad}<Item class="${inst.className}" referent="${nextRef()}"><Properties>${props}</Properties>${children ? '\n' + children + '\n' + pad : ''}</Item>`;
}

// ---------- src/ → instancias ----------
function fromFile(full) {
  const file = basename(full);
  const source = readFileSync(full, 'utf8').replace(/\r\n/g, '\n');
  let m;
  if ((m = file.match(/^(.+)\.server\.luau?$/))) return { className: 'Script', name: m[1], props: [['source', 'Source', source]], children: [] };
  if ((m = file.match(/^(.+)\.client\.luau?$/))) return { className: 'LocalScript', name: m[1], props: [['source', 'Source', source]], children: [] };
  if ((m = file.match(/^(.+)\.luau?$/))) return { className: 'ModuleScript', name: m[1], props: [['source', 'Source', source]], children: [] };
  return null;
}

function fromDir(dir, name = basename(dir)) {
  const children = [];
  for (const entry of readdirSync(dir).sort()) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) children.push(fromDir(full));
    else {
      const inst = fromFile(full);
      if (inst) children.push(inst);
    }
  }
  return { className: 'Folder', name, props: [], children };
}

const service = (className, props = [], children = []) => ({ className, name: className, props, children });

// --run-id=XXXX identifica una ejecución de pruebas (lo pone tools/ejecutar-pruebas.ps1)
const RUN_ID = (process.argv.find((a) => a.startsWith('--run-id=')) || '--run-id=manual').slice('--run-id='.length);
// --retraso=0.1 simula esa latencia de red (segundos) durante las pruebas; --suites=Eco,Ecos corre solo esas suites
const argValue = (name) => (process.argv.find((a) => a.startsWith(`--${name}=`)) || '').slice(name.length + 3);
const TEST_LAG = argValue('retraso');
const TEST_SUITES = argValue('suites');
const markerValue = (name, value) => ({ className: 'StringValue', name, props: [['string', 'Value', value]], children: [] });

const runSpeed = configNumber('RunSpeed');
const jumpHeight = configNumber('JumpHeight');
const gravity = configNumber('Gravity');

// withTests: añade tests/ y la carpeta-marca que hace que el plugin de pruebas se active.
// Desarrollo: se aparece en la Grieta (mazmorra de muestra) con su iluminación nocturna.
// Pruebas: solo el laboratorio, con luz de día (las pruebas miden en él y buscan UN compañero de combate).
function workspaceTree(withTests) {
  const maps = buildMovementLab({ labSpawn: withTests, testEnemies: withTests });
  if (!withTests) maps[0].children.push(buildDungeon());
  return maps;
}

function lightingService(withTests) {
  if (withTests) {
    return service('Lighting', [
      ['token', 'Technology', 3], // ShadowMap: sombras del sol (sin esto Studio avisa que la iluminación de compatibilidad está obsoleta)
      ['float', 'ClockTime', 14.5],
      ['float', 'Brightness', 2],
      ['color3', 'Ambient', [0.27, 0.29, 0.35]],
      ['color3', 'OutdoorAmbient', [0.5, 0.52, 0.58]],
    ]);
  }
  const lighting = dungeonLighting();
  return service('Lighting', lighting.props, lighting.children);
}

function placeTree(withTests) {
  const testClient = withTests ? fromDir(join(ROOT, 'tests', 'client')).children : [];
  const testServer = withTests ? fromDir(join(ROOT, 'tests', 'server')).children : [];
  return [
    service('Workspace', [['float', 'Gravity', gravity]], workspaceTree(withTests)),
    lightingService(withTests),
    service('ReplicatedStorage', [], [
      fromDir(join(SRC, 'shared'), 'Shared'),
      ...(withTests
        ? [{
            className: 'Folder',
            name: 'UmbralPruebasAutomaticas',
            props: [],
            children: [
              markerValue('RunId', RUN_ID),
              ...(TEST_LAG ? [markerValue('Retraso', TEST_LAG)] : []),
              ...(TEST_SUITES ? [markerValue('Suites', TEST_SUITES)] : []),
            ],
          }]
        : []),
    ]),
    service('ServerScriptService', [], [...fromDir(join(SRC, 'server')).children, ...testServer]),
    service(
      'StarterPlayer',
      [
        ['token', 'GameSettingsAvatar', 1], // R15
        ['bool', 'EnableMouseLockOption', false], // Shift es el Paso, no el bloqueo del mouse
        ['float', 'CharacterWalkSpeed', runSpeed],
        ['bool', 'CharacterUseJumpPower', false],
        ['float', 'CharacterJumpHeight', jumpHeight],
        ['float', 'CameraMaxZoomDistance', 40],
        ['float', 'CameraMinZoomDistance', 6],
      ],
      [
        { className: 'StarterPlayerScripts', name: 'StarterPlayerScripts', props: [], children: [...fromDir(join(SRC, 'client')).children, ...testClient] },
        {
          className: 'StarterCharacterScripts',
          name: 'StarterCharacterScripts',
          props: [],
          // "Health" vacío: reemplaza la regeneración automática de Roblox (la vida la recupera RecoveryService)
          children: [{ className: 'Script', name: 'Health', props: [['source', 'Source', '-- Vacío a propósito: la vida la recupera RecoveryService en el servidor.']], children: [] }],
        },
      ],
    ),
  ];
}

const HEADER = '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">';
const count = (insts) => insts.reduce((n, i) => n + 1 + count(i.children || []), 0);

function writeModel(path, items, meta = '') {
  const xml = `${HEADER}\n${meta}${items.map((t) => serialize(t)).join('\n')}\n</roblox>\n`;
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, xml, 'utf8');
  console.log(`Listo: ${path} · ${count(items)} instancias · ${Buffer.byteLength(xml)} bytes`);
}

const args = new Set(process.argv.slice(2));
const META = '<Meta name="ExplicitAutoJoints">true</Meta>\n';

writeModel(OUT, placeTree(false), META);

// --beta: candidato de lanzamiento (build/UMBRAL-Beta.rbxlx). Mismo árbol que el de desarrollo (sin tests/ ni la
// marca del plugin de pruebas), tras comprobar que todas las animaciones tienen su ID publicado.
if (args.has('--beta')) {
  const ids = readFileSync(join(SRC, 'shared', 'Config', 'AnimacionesSubidas.luau'), 'utf8').match(/rbxassetid:\/\/\d+/g) || [];
  const library = readFileSync(join(SRC, 'shared', 'Combat', 'AnimationLibrary.luau'), 'utf8');
  if (ids.length < 40) throw new Error(`Faltan IDs de animaciones publicadas: hay ${ids.length} de 40`);
  const names = (insts) => insts.flatMap((i) => [i.name, ...names(i.children || [])]);
  const all = names(placeTree(false));
  for (const banned of ['UmbralPruebasAutomaticas', 'PruebasServidor', 'PruebasRunner']) {
    if (all.includes(banned)) throw new Error(`El candidato no debe incluir las pruebas (${banned})`);
  }
  if (!library) throw new Error('No se encontró AnimationLibrary');
  writeModel(join(ROOT, 'build', 'UMBRAL-Beta.rbxlx'), placeTree(false), META);
}

if (args.has('--pruebas')) {
  writeModel(join(ROOT, 'build', 'UMBRAL-Pruebas.rbxlx'), placeTree(true), META);
}

if (args.has('--instalar-plugin')) {
  const pluginPath = join(ROOT, 'build', 'UmbralPruebas.rbxmx');
  const plugin = fromFile(join(ROOT, 'tools', 'plugin', 'UmbralPruebas.server.luau'));
  writeModel(pluginPath, [plugin]);
  const pluginsDir = join(process.env.LOCALAPPDATA, 'Roblox', 'Plugins');
  mkdirSync(pluginsDir, { recursive: true });
  copyFileSync(pluginPath, join(pluginsDir, 'UmbralPruebas.rbxmx'));
  console.log(`Plugin instalado en: ${join(pluginsDir, 'UmbralPruebas.rbxmx')}`);
}
