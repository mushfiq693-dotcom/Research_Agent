#!/bin/bash
set -e

SERVICE_NAME="com.personalresearchagent.keychain"

echo "=================================================="
echo " Personal Research Agent - API Key Setup Utility  "
echo "=================================================="
echo "This script securely saves your API keys directly into the macOS Keychain."
echo ""

# 1. OpenRouter API Key
read -sp "Enter your OpenRouter API Key (sk-or-v1-...): " OPENROUTER_KEY
echo ""
if [ -n "$OPENROUTER_KEY" ]; then
    # Delete existing if present, then add
    security delete-generic-password -s "$SERVICE_NAME" -a "openrouter_api_key" 2>/dev/null || true
    security add-generic-password -s "$SERVICE_NAME" -a "openrouter_api_key" -w "$OPENROUTER_KEY" -U
    echo "✅ OpenRouter API Key saved to macOS Keychain."
else
    echo "⚠️ OpenRouter API Key skipped (empty)."
fi

echo ""

# 2. Brave Search API Key
read -sp "Enter your Brave Search API Key (BSA...): " BRAVE_KEY
echo ""
if [ -n "$BRAVE_KEY" ]; then
    security delete-generic-password -s "$SERVICE_NAME" -a "brave_search_api_key" 2>/dev/null || true
    security add-generic-password -s "$SERVICE_NAME" -a "brave_search_api_key" -w "$BRAVE_KEY" -U
    echo "✅ Brave Search API Key saved to macOS Keychain."
else
    echo "⚠️ Brave Search API Key skipped (empty)."
fi

echo ""
echo "🎉 Setup complete! You can now run the app via:"
echo "   swift run PersonalResearchAgent"
echo "   or open PersonalResearchAgent.app"
