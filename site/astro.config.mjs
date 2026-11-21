import starlight from '@astrojs/starlight'
import { defineConfig } from 'astro/config'

export default defineConfig({
  site: 'https://sunpm.github.io',
  base: '/codex-quota',
  devToolbar: { enabled: false },
  integrations: [
    starlight({
      title: 'Codex Quota',
      defaultLocale: 'root',
      locales: { root: { label: '简体中文', lang: 'zh-CN' } },
      logo: { src: '../src-tauri/icons/128x128.png' },
      favicon: '/favicon.png',
      social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/sunpm/codex-quota' }],
      sidebar: [
        { label: '下载', link: '/' },
        { label: '安装与首次打开', link: '/install/' },
        { slug: 'usage' },
      ],
      components: { Hero: './src/components/DownloadHero.astro' },
      customCss: ['./src/theme.css'],
    }),
  ],
  vite: {
    server: { fs: { allow: ['.', '../docs', '../src-tauri/icons'] } },
    build: { license: { fileName: 'licenses.md' } },
  },
})
