const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const read = (path) => readFileSync(join(__dirname, '..', path), 'utf8').replace(/\r\n/g, '\n');

function job(source, name) {
  const start = source.indexOf(`\n  ${name}:`);
  assert.notEqual(start, -1, `Missing ${name} job`);
  const rest = source.slice(start + 1);
  const next = rest.slice(1).search(/^  [a-z][a-z0-9_-]*:/m);
  return next === -1 ? rest : rest.slice(0, next + 1);
}

const expectedAndroidArtifacts = [
  ['armeabi-v7a', 'Flutify-${{ env.BUILD_LABEL }}-android-armeabi-v7a.apk'],
  ['arm64-v8a', 'Flutify-${{ env.BUILD_LABEL }}-android-arm64-v8a.apk'],
  ['x86_64', 'Flutify-${{ env.BUILD_LABEL }}-android-x86_64.apk'],
  ['universal', 'Flutify-${{ env.BUILD_LABEL }}-android-universal.apk'],
];

test('Build exposes each of the four Android APKs as a separate artifact', () => {
  const build = read('.github/workflows/build.yml');
  const android = job(build, 'android');
  for (const [abi, filename] of expectedAndroidArtifacts) {
    assert.match(android, new RegExp(`name: android-${abi}`));
    assert.ok(android.includes(filename), `Missing APK artifact path for ${abi}`);
  }
  assert.equal((android.match(/uses: actions\/upload-artifact@v4/g) || []).length, 4);
});

test('release assembly downloads the four separate Android artifacts', () => {
  const build = read('.github/workflows/build.yml');
  assert.match(build, /pattern: '\{android-\*,windows-\*,macos,linux\}'/);
  assert.match(build, /merge-multiple: true/);
});

test('Self-test exposes each ABI and universal APK separately too', () => {
  const selfTest = read('.github/workflows/self-test.yml');
  const android = job(selfTest, 'android');
  for (const abi of ['armeabi-v7a', 'arm64-v8a', 'x86_64', 'universal']) {
    assert.match(android, new RegExp(`name: self-test-android-${abi}`));
  }
  assert.equal((android.match(/uses: actions\/upload-artifact@v4/g) || []).length, 4);
});
