import unittest

from verify_android_apks import verify_application_id, verify_certificate


class PackageIdentityTest(unittest.TestCase):
    def test_expected_fork_package_is_accepted(self):
        verify_application_id("package: name='com.flutify.music.flutify_app.fork' versionCode='7'")

    def test_ordinary_package_and_missing_package_are_rejected(self):
        for metadata in ("package: name='com.flutify.music.flutify_app' versionCode='7'", "no package metadata"):
            with self.subTest(metadata=metadata), self.assertRaises(ValueError):
                verify_application_id(metadata)


class CertificateTest(unittest.TestCase):
    pinned = 'ab' * 32

    def test_legacy_and_sdk_range_signers(self):
        for label in ('#1', '(minSdkVersion=28, maxSdkVersion=32)',
                      '(minSdkVersion=33, maxSdkVersion=2147483647)'):
            with self.subTest(label=label):
                verify_certificate(f'Signer {label} certificate SHA-256 digest: {self.pinned.upper()}', self.pinned)

    def test_all_sdk_ranges_must_match(self):
        lines = [f'Signer ({sdk}) certificate SHA-256 digest: {self.pinned}'
                 for sdk in ('minSdkVersion=28, maxSdkVersion=32', 'minSdkVersion=33, maxSdkVersion=2147483647')]
        verify_certificate('\n'.join(lines), self.pinned)
        with self.assertRaises(ValueError):
            verify_certificate('\n'.join(lines) + '\nSigner #2 certificate SHA-256 digest: ' + 'cd' * 32, self.pinned)

    def test_apksigner_v2_v3_labels(self):
        lines = [f'{label} certificate SHA-256 digest: {self.pinned}'
                 for label in ('V2 Signer:', 'V3 Signer:', 'V3.1 Signer:')]
        verify_certificate('Verifies\nNumber of signers: 1\n' + '\n'.join(lines), self.pinned)
        with self.assertRaises(ValueError):
            verify_certificate('\n'.join(lines) + '\nV3 Signer: certificate SHA-256 digest: ' + 'cd' * 32, self.pinned)

    def test_missing_wrong_malformed_or_other_hashes_fail(self):
        for output in ('', 'Signer #1 certificate SHA-256 digest: broken',
                       'Signer #1 certificate SHA-256 digest: ' + 'cd' * 32,
                       'Signer #1 public key SHA-256 digest: ' + self.pinned,
                       'Source Stamp Signer certificate SHA-256 digest: ' + self.pinned):
            with self.subTest(output=output), self.assertRaises(ValueError):
                verify_certificate(output, self.pinned)


if __name__ == '__main__':
    unittest.main()
