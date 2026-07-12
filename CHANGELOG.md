# Changelog

## [1.4.0](https://github.com/willzhu16/platform/compare/v1.3.0...v1.4.0) (2026-07-12)


### Features

* **ci:** shellcheck the bootstrap scripts in selftest ([61e8e27](https://github.com/willzhu16/platform/commit/61e8e27b2a3946ceabbd03f16dc645b6bc077744))


### Bug Fixes

* **scripts:** close the bootstrap gaps found by the canary drill ([42682e7](https://github.com/willzhu16/platform/commit/42682e7a6c0da7dc170e8425632db3a6e833952c))
* **scripts:** close the bootstrap gaps found by the canary drill ([37e02d4](https://github.com/willzhu16/platform/commit/37e02d432e6da7662ab571f13e02eea60bcb8f91))

## [1.3.0](https://github.com/willzhu16/platform/compare/v1.2.0...v1.3.0) (2026-07-11)


### Features

* add the athena-sync reusable workflow (spec 04 §3) ([737e9a8](https://github.com/willzhu16/platform/commit/737e9a80e3c5695cae162beb0f8814da4f5b1f75))
* athena-sync workflow and template-render selftest ([724c08b](https://github.com/willzhu16/platform/commit/724c08bf485bb09cebe242353f00abab272bbd16))
* **ci:** render both templates in selftest and run their gates ([deb49cc](https://github.com/willzhu16/platform/commit/deb49cc94bd07403cf759fd690b49ef4aaf001e2))

## [1.2.0](https://github.com/willzhu16/platform/compare/v1.1.0...v1.2.0) (2026-07-11)


### Features

* add spec 01 CI reusable workflows ([8efaacc](https://github.com/willzhu16/platform/commit/8efaacca907bda04a475858c8edbd6e5e3c9fa5f))
* add spec 02 security pipeline ([9f77a8e](https://github.com/willzhu16/platform/commit/9f77a8e4d8c34f3a6a32e7859a013abb09902e99))
* add spec 03 templates + bootstrap ([704a9dd](https://github.com/willzhu16/platform/commit/704a9dd46e729a380455020dc8b542c973e37a97))
* add spec 05 handbook seeds ([b5f5fb6](https://github.com/willzhu16/platform/commit/b5f5fb6d6a875b8960157fcda6d986f497919e30))
* add spec 07 release and preview reusable workflows ([955de22](https://github.com/willzhu16/platform/commit/955de22db4ef9260b30fcb010b8e070e0607c295))
* add spec 07 release and preview reusable workflows ([8db96ba](https://github.com/willzhu16/platform/commit/8db96bae4ba8d0a8789761945ae7c7961edd0c08))
* add specs 03+05 and the 2026-07-09 fix pass ([4503b88](https://github.com/willzhu16/platform/commit/4503b8811209af3d9c342daea1365e791762e3ad))
* **ci:** lint every workflow with actionlint in selftest ([d39369c](https://github.com/willzhu16/platform/commit/d39369c2ea6a33342ce2a46d6b404889d5c5c4d0))
* land spec 07 release flow and fix v1 tag automation ([ba04e12](https://github.com/willzhu16/platform/commit/ba04e1274e2160766e98a25eb993ab0e28ddd09c))


### Bug Fixes

* **cadence:** sync issue checklists with handbook wording ([4a19b1c](https://github.com/willzhu16/platform/commit/4a19b1c7661dd6c73deb951d88d8dd8c0b97ae5f))
* **ci:** move actionlint suppression into its config file ([7d7dcb2](https://github.com/willzhu16/platform/commit/7d7dcb2ddf6967c2d1feeefc0e3bea47db557d41))
* **ci:** point setup-node cache at lockfile paths, not a directory ([fb18e97](https://github.com/willzhu16/platform/commit/fb18e9710f5bdb8b64596dac058ddefec47f4621))
* **ci:** resolve pnpm version from the working directory's package.json ([fc56d78](https://github.com/willzhu16/platform/commit/fc56d78a497857949bb9273f2dfc00066b597897))
* **release:** dispatch the v1 tag mover explicitly ([ff5dcc7](https://github.com/willzhu16/platform/commit/ff5dcc7e322dfe5b7a25bf620cd695ca60867268))
* **release:** harden tag handling in the reusable release flow ([ac78a41](https://github.com/willzhu16/platform/commit/ac78a418c042e5d6d931903c752d84105a8d87cf))
* **release:** keep plain vX.Y.Z tags via include-component-in-tag false ([6b6c423](https://github.com/willzhu16/platform/commit/6b6c4235a3d3ef21d9326402faa0e628cfbe8af9))
* **scripts:** harden new-project.sh and pin sops download URL ([1ca7865](https://github.com/willzhu16/platform/commit/1ca7865242cb1f6f4cd0a89ee86d2f6f7a42173d))
* **security:** fetch onboarding gitleaks config from platform ([eeff0f1](https://github.com/willzhu16/platform/commit/eeff0f1b0cd6b8043c660eaabbebb11c57e08bea))
* **security:** resolve platform ref from workflow_ref ([a16daf8](https://github.com/willzhu16/platform/commit/a16daf8c43d0062db4f282b01ad286d1c4da5483))
* **security:** resolve platform ref via job.workflow_* context ([f09b1a5](https://github.com/willzhu16/platform/commit/f09b1a561d4bda9479fe9fcbd82a39f04231e653))
* **templates:** drop empty wrangler env blocks ([2cf0905](https://github.com/willzhu16/platform/commit/2cf0905d482090ea8a8a2da5e38c32e8ea0769b4))
* **templates:** fail closed on siteverify outage and fix py-tool stack ([f45f003](https://github.com/willzhu16/platform/commit/f45f0037c4d901ce90e360b3cf4ed42ed561a197))
* **templates:** gate cron question and cancel superseded runs ([75a0add](https://github.com/willzhu16/platform/commit/75a0adda3745b1e9fc3146d5730bc8a5d3dc897e))
* **templates:** hand release tags over to release.yml explicitly ([4fbbd5b](https://github.com/willzhu16/platform/commit/4fbbd5b9858a80cfd08cc5062426f5ea68b02071))
* **templates:** log schema keys win over caller fields ([dfbf03f](https://github.com/willzhu16/platform/commit/dfbf03f4cdd41269a57b798e2d551e0f6881481c))
* **templates:** skip draft previews and cancel superseded runs ([01d3132](https://github.com/willzhu16/platform/commit/01d31325d3223147df6b4a65f9f4f26197ddb693))

## [1.1.0](https://github.com/willzhu16/platform/compare/platform-v1.0.0...platform-v1.1.0) (2026-07-06)


### Features

* add spec 01 CI reusable workflows ([8efaacc](https://github.com/willzhu16/platform/commit/8efaacca907bda04a475858c8edbd6e5e3c9fa5f))
* add spec 02 security pipeline ([9f77a8e](https://github.com/willzhu16/platform/commit/9f77a8e4d8c34f3a6a32e7859a013abb09902e99))
