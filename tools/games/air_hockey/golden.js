// tools/games/air_hockey/golden.js: golden states for the air hockey port, from the owner's own physics.js.
// Runs docs/reference/air_hockey/physics.js (AER / 01, unchanged) through scripted and seeded matches and writes
// every input and the states they led to into tests/golden/air_hockey.json. The Luau port
// (src/shared/Minigames/AirHockey/Sim.luau) replays the same inputs in tests/unit/air_hockey_golden.spec.luau and
// must match every recorded state to 1e-9.
// Run: node tools/games/air_hockey/golden.js   (from the repository root; Node 18 or later, no packages)
// A case: { name, human, computer, difficulty, dt?, setup? (fields written before the first tick), ticks,
//   inputs: [[tick, side, x, y] | [tick, -1]] (before tick `tick`: setTarget(side, [x, y]) | serve() if the
//   countdown is running), every (a state is recorded after every `every`-th tick, and after the last),
//   states: [[tick, puck.x, puck.y, vel.x, vel.y, p0.x, p0.y, p1.x, p1.y, score0, score1, countdown, hitSerial,
//   goalSerial, winner, serveSide, lastGoal]] }
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..', '..');
const SOURCE = path.join(ROOT, 'docs', 'reference', 'air_hockey', 'physics.js');
const OUT = path.join(ROOT, 'tests', 'golden', 'air_hockey.json');
const HockeyGame = new Function(fs.readFileSync(SOURCE, 'utf8') + '\nreturn HockeyGame;')();

// MINSTD: exact in doubles, so a case could be regenerated anywhere (the inputs are stored all the same).
function rng(seed) {
  let x = seed % 2147483647;
  if (x <= 0) x += 2147483646;
  return () => {
    x = (x * 48271) % 2147483647;
    return (x - 1) / 2147483646;
  };
}

function state(g, tick) {
  return [tick, g.puck[0], g.puck[1], g.velocity[0], g.velocity[1], g.paddles[0].p[0], g.paddles[0].p[1],
    g.paddles[1].p[0], g.paddles[1].p[1], g.score[0], g.score[1], g.countdown, g.hitSerial, g.goalSerial,
    g.winner, g.serveSide, g.lastGoal];
}

// run(spec, drive): drive(g, tick) returns the inputs to apply before that tick (and may look at the game, as a
// player would). The game stops early when it is won (a won game no longer moves).
function run(spec, drive) {
  const g = new HockeyGame();
  g.difficulty = spec.difficulty ?? 1;
  const setup = spec.setup || {};
  if (setup.puck) g.puck = setup.puck.slice();
  if (setup.velocity) g.velocity = setup.velocity.slice();
  if (setup.countdown !== undefined) g.countdown = setup.countdown;
  if (setup.score) g.score = setup.score.slice();
  if (setup.paddle0) g.paddles[0].p = setup.paddle0.slice(), g.paddles[0].target = setup.paddle0.slice();
  if (setup.paddle1) g.paddles[1].p = setup.paddle1.slice(), g.paddles[1].target = setup.paddle1.slice();
  const dt = spec.dt ?? 1 / 240;
  const inputs = [], states = [];
  let tick = 0;
  for (; tick < spec.ticks && g.winner < 0; tick++) {
    for (const input of (drive ? drive(g, tick) : [])) {
      inputs.push(input);
      if (input[1] < 0) { if (g.countdown > 0) g.serve(); } else g.setTarget(input[1], [input[2], input[3]]);
    }
    g.tick(dt, spec.human, spec.computer);
    if ((tick + 1) % spec.every === 0) states.push(state(g, tick + 1));
  }
  if (states.length === 0 || states[states.length - 1][0] !== tick) states.push(state(g, tick));
  return { ...spec, ticks: tick, dt, inputs, states };
}

// A person at the table, roughly: every `period` ticks (a mouse at 60 Hz moves a target every fourth tick) the
// hand goes somewhere new: home, under the puck, or through it toward the far goal.
function hand(side, seed, period, vigour) {
  const r = rng(seed);
  let mood = 0, until = 0;
  return (g, tick) => {
    if (tick % period !== 0) return [];
    const s = side ? 1 : -1, p = g.puck;
    if (tick >= until) { mood = Math.floor(r() * 4); until = tick + 24 + Math.floor(r() * 120); }
    let x, y;
    if (mood === 0) { x = (r() - .5) * .9; y = s * (.25 + r() * .8); }
    else if (mood === 1) { x = p[0] + (r() - .5) * .05; y = s * .95; }
    else if (p[1] * s > 0) { x = p[0] + (r() - .5) * .04 * vigour; y = p[1] - s * (.05 + r() * .5) * vigour; }
    else { x = p[0] * .5; y = s * (.5 + r() * .3); }
    const out = [[tick, side, x, y]];
    if (g.countdown > 0 && r() < .02) out.push([tick, -1]);
    return out;
  };
}
const both = (a, b) => (g, tick) => a(g, tick).concat(b(g, tick));

const cases = [];
const still = { countdown: 0 };
// rails: fast shots at every angle from several places (no mallet in the way: they are parked in the corners)
{
  const r = rng(11);
  for (let i = 0; i < 12; i++) {
    const a = r() * Math.PI * 2, v = 2 + r() * 5.5;
    cases.push(run({ name: `rails ${i}`, human: 0, computer: false, every: 1, ticks: 200,
      setup: { ...still, puck: [(r() - .5) * 1.1, (r() - .5) * 2.1], velocity: [Math.cos(a) * v, Math.sin(a) * v],
        paddle0: [-.556, -1.106], paddle1: [.556, 1.106] } }));
  }
}
// goal posts: straight at each post, a little to either side of it, at several speeds
{
  let i = 0;
  for (const sx of [-1, 1]) for (const sy of [-1, 1]) for (const off of [-.03, -.012, 0, .009, .028]) {
    cases.push(run({ name: `post ${i++}`, human: 0, computer: false, every: 1, ticks: 100,
      setup: { ...still, puck: [sx * (.22 + off), sy * .7], velocity: [off * 2, sy * (3 + i * .2)],
        paddle0: [-.556, -1.106], paddle1: [.556, 1.106] } }));
  }
}
// goals: into each slot straight and at an angle, along the slot's side walls, and the seventh goal
{
  let i = 0;
  for (const sy of [-1, 1]) for (const [x, vx, vy] of [[0, 0, 7.5], [.1, 1.5, 6], [-.15, -.6, 3], [0, 7.4, .1], [.18, .3, 2]]) {
    cases.push(run({ name: `goal ${i++}`, human: 0, computer: false, every: 1, ticks: 160,
      setup: { ...still, puck: [x, sy * 1.0], velocity: [vx, sy * vy], paddle0: [-.556, -1.106], paddle1: [.556, 1.106] } }));
  }
  cases.push(run({ name: 'goal: the seventh ends the match', human: 0, computer: false, every: 1, ticks: 240,
    setup: { ...still, score: [6, 3], puck: [0, 1.0], velocity: [.2, 5], paddle0: [-.556, -1.106], paddle1: [.556, 1.106] } }));
}
// mallets: a still one blocks, a moving one strikes, a serve after the countdown
cases.push(run({ name: 'mallet: a still mallet blocks', human: 0, computer: false, every: 1, ticks: 360,
  setup: { ...still, puck: [.02, -.2], velocity: [.1, -6] } }));
cases.push(run({ name: 'mallet: a strike from rest', human: 0, computer: false, every: 1, ticks: 480,
  setup: { ...still, puck: [0, -.61], velocity: [0, 0] } }, (g, tick) => tick === 0 ? [[0, 0, .03, -.3]] : []));
cases.push(run({ name: 'serve: the countdown, then the serve', human: 0, computer: true, every: 1, ticks: 720 }));
cases.push(run({ name: 'serve: a tap serves at once', human: 0, computer: true, every: 1, ticks: 480 },
  (g, tick) => tick === 30 ? [[30, -1]] : []));
// two people (the computer off): both hands driven, every state of the first seconds, then sampled
cases.push(run({ name: 'two people: seed 1', human: 0, computer: false, every: 1, ticks: 720 },
  both(hand(0, 101, 4, 1), hand(1, 202, 4, 1))));
cases.push(run({ name: 'two people: seed 2, a long rally', human: 0, computer: false, every: 16, ticks: 240 * 60 },
  both(hand(0, 303, 4, 1.3), hand(1, 404, 3, .8))));
// one person against the computer, either end, each difficulty
{
  let seed = 500;
  for (const human of [0, 1]) for (const [word, difficulty] of [['easy', .62], ['medium', 1], ['hard', 1.38]]) {
    cases.push(run({ name: `computer: ${word}, the person plays side ${human}`, human, computer: true, difficulty,
      every: 16, ticks: 240 * 25 }, hand(human, seed += 7, 4, 1)));
  }
}
// whole matches to seven: a person against the hard computer, and the computer left alone against a still mallet
cases.push(run({ name: 'match: to seven against the hard computer', human: 0, computer: true, difficulty: 1.38,
  every: 16, ticks: 240 * 600 }, hand(0, 777, 4, 1.1)));
cases.push(run({ name: 'match: to seven, the person never moves', human: 1, computer: true, difficulty: 1,
  every: 16, ticks: 240 * 600 }));

// V8's Math.hypot, as the port writes it out: checked here so a Node that rounds differently says so
{
  const r = rng(5);
  const mine = (x, y) => { const ax = Math.abs(x), ay = Math.abs(y), m = Math.max(ax, ay); if (m === 0) return 0;
    const nx = ax / m, ny = ay / m; return Math.sqrt(nx * nx + ny * ny) * m; };
  for (let i = 0; i < 200000; i++) {
    const x = (r() - .5) * 20 * r(), y = (r() - .5) * 20 * r();
    if (mine(x, y) !== Math.hypot(x, y)) throw new Error(`Math.hypot(${x}, ${y}) is not the scaled form on this Node`);
  }
}

const won = cases.filter(c => c.states[c.states.length - 1][14] >= 0).map(c => c.name);
const out = { source: 'docs/reference/air_hockey/physics.js', tool: 'tools/games/air_hockey/golden.js',
  node: process.version, decay: Math.exp(-.08 * (1 / 240)), cases };
fs.writeFileSync(OUT, JSON.stringify(out));
const n = cases.reduce((a, c) => a + c.states.length, 0);
console.log(`${cases.length} cases, ${n} states, ${cases.reduce((a, c) => a + c.inputs.length, 0)} inputs -> ${path.relative(ROOT, OUT)} (${(fs.statSync(OUT).size / 1024).toFixed(0)} kB)`);
console.log(`decay ${Math.exp(-.08 * (1 / 240)).toPrecision(17)}; won: ${won.join('; ')}`);
for (const c of cases) if (c.name.startsWith('match') || c.name.startsWith('computer') || c.name.startsWith('two')) {
  const s = c.states[c.states.length - 1];
  console.log(`  ${c.name}: ${c.ticks} ticks, ${s[9]}-${s[10]}, ${s[12]} hits`);
}
