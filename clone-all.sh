#!/bin/bash
# Enterprise AI Platform - 一键克隆所有子仓库
set -e

echo "Cloning enterprise-ai-platform..."
git clone https://github.com/Carlelst/enterprise-ai-platform.git
cd enterprise-ai-platform

echo "Cloning RAGFlow tools (fork)..."
git clone https://github.com/Carlelst/ragflow.git ragflow

echo "Cloning ef_agent_kits (internal)..."
git clone git@git.enflame.cn:hw/spt/ef_agent_kits.git ef_agent_kits

echo "Cloning Dify..."
git clone https://github.com/Carlelst/dify.git dify 2>/dev/null || echo "dify: skip (may not exist)"

echo "Done! Run: cd enterprise-ai-platform"
