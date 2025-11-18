# GitBook Deployment Guide

This guide covers the easiest ways to deploy your documentation to GitBook.

---

## 🚀 Option 1: GitBook.com (Easiest - Recommended)

### Step 1: Create GitBook Account

1. Go to [gitbook.com](https://www.gitbook.com)
2. Sign up with GitHub (recommended) or email
3. Verify your account

### Step 2: Create New Space

1. Click **"Create new"** → **"Space"**
2. Choose **"Import from GitHub"** (if you have the repo on GitHub)
   - OR choose **"Start from scratch"** and upload files manually

### Step 3: Import Your Documentation

#### Option A: Import from GitHub (Recommended)

1. **Push your repo to GitHub** (if not already):
   ```bash
   git init
   git add .
   git commit -m "Add GitBook documentation"
   git remote add origin https://github.com/yourusername/L2BundlerMachine.git
   git push -u origin main
   ```

2. In GitBook:
   - Select **"Import from GitHub"**
   - Authorize GitBook to access your GitHub
   - Select your repository: `L2BundlerMachine`
   - Select branch: `main` (or your default branch)
   - Set root path: `gitbook-docs/`
   - Click **"Import"**

3. GitBook will automatically:
   - Detect your markdown files
   - Generate navigation from folder structure
   - Create a beautiful documentation site

#### Option B: Manual Upload

1. In GitBook, select **"Start from scratch"**
2. Go to **Settings** → **Content** → **Import**
3. Upload your `gitbook-docs` folder
4. GitBook will process the files

### Step 4: Configure Navigation

GitBook will auto-generate navigation, but you can customize:

1. Go to **Settings** → **Content** → **Navigation**
2. GitBook reads your `SUMMARY.md` file automatically
3. Or manually organize pages in the sidebar

### Step 5: Customize Appearance

1. Go to **Settings** → **Appearance**
2. Choose a theme (Modern, Classic, etc.)
3. Customize colors to match your brand
4. Add your logo

### Step 6: Publish

1. Click **"Publish"** button
2. Choose visibility:
   - **Public**: Anyone can view
   - **Private**: Only invited users
   - **Unlisted**: Accessible via direct link
3. Your documentation is now live!

**Your GitBook URL will be**: `https://your-space.gitbook.io/l2-bundler-machine`

---

## 📝 Option 2: GitBook CLI (Self-Hosted)

### Install GitBook CLI

```bash
npm install -g gitbook-cli
```

### Build Documentation

```bash
cd gitbook-docs
gitbook install  # Install plugins
gitbook build    # Build static site
```

### Serve Locally

```bash
gitbook serve    # View at http://localhost:4000
```

### Deploy to GitHub Pages

```bash
# Build the site
gitbook build

# Deploy to GitHub Pages
cd _book
git init
git add .
git commit -m "Deploy GitBook"
git branch -M gh-pages
git remote add origin https://github.com/yourusername/L2BundlerMachine.git
git push -u origin gh-pages
```

**Enable GitHub Pages**:
1. Go to repository Settings → Pages
2. Select source: `gh-pages` branch
3. Your site will be at: `https://yourusername.github.io/L2BundlerMachine/`

---

## 🌐 Option 3: MkDocs (Alternative)

MkDocs is another great option for markdown documentation.

### Install MkDocs

```bash
pip install mkdocs mkdocs-material
```

### Create mkdocs.yml

Create `mkdocs.yml` in your `gitbook-docs` folder:

```yaml
site_name: L1-L2 Cross-Chain Yield Aggregator
site_description: Production-ready cross-chain yield aggregation system
site_author: Your Name

theme:
  name: material
  palette:
    primary: indigo
    accent: indigo
  features:
    - navigation.tabs
    - navigation.sections
    - toc.integrate

nav:
  - Home: README.md
  - Architecture: architecture/README.md
  - Contracts: contracts/README.md
  - Factory: factory/README.md
  - Strategies: strategies/README.md
  - Bridge: bridge/README.md
  - User Guide: user-guide/README.md
  - Deployment: deployment/README.md
  - Roadmap: ROADMAP.md
  - Testing: TESTING.md
```

### Build and Serve

```bash
cd gitbook-docs
mkdocs build    # Build site
mkdocs serve    # View at http://localhost:8000
```

### Deploy to GitHub Pages

```bash
mkdocs gh-deploy
```

---

## 🎯 Recommended Setup for Grant Proposal

### For Best Results:

1. **Use GitBook.com** (Option 1) - Easiest and most professional
2. **Import from GitHub** - Keeps documentation in sync
3. **Make it Public** - Easy to share with grant reviewers
4. **Customize Branding** - Add your logo and colors

### Quick Start Checklist

- [ ] Push documentation to GitHub
- [ ] Create GitBook account
- [ ] Import from GitHub repository
- [ ] Set root path to `gitbook-docs/`
- [ ] Customize appearance (logo, colors)
- [ ] Review auto-generated navigation
- [ ] Publish as public space
- [ ] Share link with grant reviewers

---

## 🔗 GitBook Features

### Automatic Features

- ✅ **Auto-navigation**: Reads folder structure
- ✅ **Search**: Built-in search functionality
- ✅ **Mobile Responsive**: Works on all devices
- ✅ **Version Control**: Syncs with GitHub
- ✅ **Collaboration**: Multiple editors
- ✅ **Analytics**: View traffic and engagement

### Customization Options

- **Themes**: Modern, Classic, Custom
- **Colors**: Match your brand
- **Logo**: Add your logo
- **Custom Domain**: Use your own domain
- **Integrations**: Slack, Discord, etc.

---

## 📊 Comparison

| Feature | GitBook.com | GitBook CLI | MkDocs |
|---------|-------------|-------------|--------|
| **Ease of Use** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| **Hosting** | Included | Self-host | Self-host |
| **Cost** | Free (public) | Free | Free |
| **Custom Domain** | ✅ | ✅ | ✅ |
| **GitHub Sync** | ✅ | Manual | Manual |
| **Search** | ✅ Built-in | ✅ | ✅ |
| **Mobile** | ✅ | ✅ | ✅ |

---

## 🚀 Quick Deploy (5 Minutes)

### Fastest Path:

```bash
# 1. Ensure your repo is on GitHub
git add gitbook-docs/
git commit -m "Add GitBook documentation"
git push

# 2. Go to gitbook.com
# 3. Click "Import from GitHub"
# 4. Select your repo
# 5. Set root: gitbook-docs/
# 6. Click "Import"
# 7. Click "Publish"
# Done! 🎉
```

---

## 💡 Tips

1. **Use SUMMARY.md**: GitBook reads this for navigation
2. **Keep Structure**: Maintain folder organization
3. **Use Relative Links**: `./contracts/README.md` not absolute paths
4. **Test Locally**: Review before publishing
5. **Update Regularly**: Keep documentation in sync with code

---

## 🔗 Resources

- [GitBook Documentation](https://docs.gitbook.com/)
- [GitBook CLI](https://github.com/GitbookIO/gitbook-cli)
- [MkDocs Documentation](https://www.mkdocs.org/)
- [MkDocs Material Theme](https://squidfunk.github.io/mkdocs-material/)

---

## 📝 Next Steps

1. Choose your deployment method (recommend GitBook.com)
2. Follow the steps above
3. Share your documentation link
4. Keep it updated as you develop

**Your documentation will be professional, searchable, and easy to share!** 🎉

