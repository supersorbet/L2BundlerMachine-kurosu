# GitBook Setup Guide

This guide will help you set up your GitBook documentation from your git repository.

## Option 1: Connect GitBook to GitHub/GitLab/Bitbucket (Recommended)

### Step 1: Push to Remote Repository

First, make sure your repository is pushed to GitHub, GitLab, or Bitbucket:

```bash
# If you haven't initialized git yet
git init
git add .
git commit -m "Initial commit: GitBook documentation"

# Add your remote repository
git remote add origin <your-repo-url>
git push -u origin main
```

### Step 2: Create GitBook Account

1. Go to [GitBook.com](https://www.gitbook.com)
2. Sign up or log in
3. Click "New Space" or "Create Space"

### Step 3: Connect Repository

1. In GitBook, select **"Import from Git"** or **"Connect Git Repository"**
2. Choose your Git provider (GitHub/GitLab/Bitbucket)
3. Authorize GitBook to access your repositories
4. Select your repository (`inkL2bundler-gitbook-docs`)
5. Choose the branch (usually `main` or `master`)
6. Set the root path if needed (should be `/` for your structure)

### Step 4: Configure GitBook

GitBook will automatically detect your `SUMMARY.md` and `README.md` files. The configuration will use:
- `SUMMARY.md` - Table of contents
- `README.md` - Homepage
- `book.json` or `.gitbook.yaml` - Configuration (if using legacy GitBook)

### Step 5: Publish

1. GitBook will automatically sync your repository
2. Changes pushed to your git repo will automatically update GitBook
3. You can preview before publishing
4. Click "Publish" to make it live

---

## Option 2: Use GitBook CLI (Local Development)

### Step 1: Install GitBook CLI

```bash
# Install Node.js if you don't have it
# Then install GitBook CLI
npm install -g gitbook-cli

# Verify installation
gitbook --version
```

### Step 2: Install GitBook Plugins

```bash
cd /home/xx/Desktop/inkL2bundler-gitbook-docs
gitbook install
```

This will install plugins specified in `book.json`.

### Step 3: Serve Locally

```bash
# Serve locally for preview
gitbook serve

# Or build static files
gitbook build
```

The documentation will be available at `http://localhost:4000`

### Step 4: Build and Deploy

```bash
# Build static HTML
gitbook build

# Output will be in _book/ directory
# You can deploy _book/ to any static hosting (GitHub Pages, Netlify, etc.)
```

---

## Option 3: Use Modern GitBook (gitbook.com)

Modern GitBook (gitbook.com) uses a different approach:

### Step 1: Create Space on GitBook.com

1. Go to [GitBook.com](https://www.gitbook.com)
2. Create a new Space
3. Choose "Import from Git"

### Step 2: Connect Repository

1. Connect your GitHub/GitLab/Bitbucket account
2. Select your repository
3. GitBook will automatically sync

### Step 3: Configure

Modern GitBook uses:
- `SUMMARY.md` for navigation (if present)
- Or you can manually organize pages in GitBook UI
- Auto-syncs on git push

---

## File Structure Requirements

Your repository should have:

```
inkL2bundler-gitbook-docs/
├── README.md          # Homepage
├── SUMMARY.md         # Table of contents (GitBook format)
├── book.json          # Legacy GitBook config (optional)
├── .gitbook.yaml      # Modern GitBook config (optional)
└── [your content files]
```

---

## Troubleshooting

### GitBook Not Detecting Files

1. Make sure `SUMMARY.md` is in the root directory
2. Check that file paths in `SUMMARY.md` are correct
3. Ensure files exist at the specified paths

### Formatting Issues

- GitBook uses Markdown with some extensions
- Code blocks should use proper syntax highlighting
- Images should use relative paths

### Sync Issues

- Make sure your git repository is connected
- Check branch name matches GitBook settings
- Verify GitBook has access to your repository

---

## Recommended Workflow

1. **Local Development**: Use GitBook CLI for local preview
   ```bash
   gitbook serve
   ```

2. **Version Control**: Commit changes to git
   ```bash
   git add .
   git commit -m "Update documentation"
   git push
   ```

3. **Auto-Sync**: GitBook automatically updates when you push to git

4. **Publish**: Use GitBook's publish feature to make it public

---

## Additional Resources

- [GitBook Documentation](https://docs.gitbook.com/)
- [GitBook Markdown Guide](https://docs.gitbook.com/content-editor/markdown)
- [GitBook CLI Documentation](https://github.com/GitbookIO/gitbook-cli)

---

## Quick Start Commands

```bash
# Initialize git (if not done)
git init
git add .
git commit -m "Initial commit"

# Push to remote
git remote add origin <your-repo-url>
git push -u origin main

# Then connect to GitBook via web interface
```

---

**Note**: Modern GitBook (gitbook.com) is recommended as it provides better UI, automatic syncing, and easier collaboration compared to the legacy CLI version.

