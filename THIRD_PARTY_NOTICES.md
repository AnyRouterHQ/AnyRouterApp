# Third-party notices

## MarkdownUI

Markdown rendering uses swift-markdown-ui (https://github.com/gonzalezreal/swift-markdown-ui), licensed under the MIT License. Copyright (c) 2020 Guillermo Gonzalez.

## llama.cpp

The GGUF engine links the official llama.cpp xcframework (https://github.com/ggml-org/llama.cpp), MIT License, Copyright (c) 2023-2026 The ggml authors.

## Test fixture

`Tests/Engines/Local/Fixtures/stories260K.gguf` is the 260K-parameter TinyStories model from https://huggingface.co/ggml-org/tiny-llamas (Andrej Karpathy's llama2.c, MIT License). It is used only to smoke-test the llama.cpp integration.

## MLX Swift and MLX Swift LM

The MLX engine uses mlx-swift (https://github.com/ml-explore/mlx-swift) and mlx-swift-lm (https://github.com/ml-explore/mlx-swift-lm), MIT License, Copyright (c) Apple Inc.

## Provider and model logos

The monochrome provider and model logos in `Design/Assets.xcassets` (`Logo-*`) come from lobe-icons (https://github.com/lobehub/lobe-icons, `@lobehub/icons-static-svg`), MIT License, Copyright (c) 2023 LobeHub. Version 1.106.0 is pinned in `scripts/logo-add.py`, which adds each mark; `Design/model-brands.json` lists them. The marks are trademarks of their owners and are shown only to identify a model's provider, or the web tool a service offers (`Logo-exa`).

## swift-transformers

Tokenizers come from swift-transformers (https://github.com/huggingface/swift-transformers), Apache License 2.0, Copyright Hugging Face.

## WhisperKit

Speech to text with a downloaded Whisper model uses WhisperKit from argmax-oss-swift (https://github.com/argmaxinc/argmax-oss-swift), MIT License, Copyright (c) 2024 argmax, inc. The Whisper models are OpenAI's (https://github.com/openai/whisper), MIT License, converted to Core ML by argmax (https://huggingface.co/argmaxinc/whisperkit-coreml).
