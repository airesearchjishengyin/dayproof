# Third-party notices

## AgentPet SpriteSlicer

`native/Vendor/AgentPet/SpriteSlicer.swift` is copied from [AgentPet](https://github.com/ntd4996/agentpet), commit `8591742895b8ea3cd412520bbf6099f771cec478`.

Copyright (c) 2026 Nguyễn Thành Đạt. MIT License; the full license is included in `native/Vendor/AgentPet/LICENSE` and in the app's Resources/ThirdParty directory.

Dayproof uses this module to load local `pet.json` + spritesheet packs. It does not copy AgentPet's account integrations, hooks, gallery or pet artwork. Dayproof's bundled vector cat is original code under this repository's MIT license. Imported pet artwork retains its own author's license; the engine license does not license third-party characters.

## Runtime and JavaScript dependencies

The locally built macOS application bundles Node.js (license available from https://github.com/nodejs/node/blob/main/LICENSE) and the production npm dependencies declared in package-lock.json. Dependency license files are retained in Resources/backend/node_modules. The build script also copies the Node runtime's LICENSE when available; Node's official distribution license is included alongside the bundled runtime.
