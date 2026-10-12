/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    screens: {
      xs: '375px',
      sm: '640px',
      md: '768px',
      lg: '1024px',
      xl: '1280px',
      '2xl': '1536px',
    },
    extend: {
      colors: {
        page: 'rgb(var(--rgb-page) / <alpha-value>)',
        surface: 'rgb(var(--rgb-surface) / <alpha-value>)',
        container: 'rgb(var(--rgb-container) / <alpha-value>)',
        'container-high': 'rgb(var(--rgb-container-high) / <alpha-value>)',
        ink: 'rgb(var(--rgb-ink) / <alpha-value>)',
        muted: 'rgb(var(--rgb-muted) / <alpha-value>)',
        border: 'rgb(var(--rgb-border) / <alpha-value>)',
        primary: {
          DEFAULT: 'rgb(var(--rgb-primary) / <alpha-value>)',
          hover: 'rgb(var(--rgb-primary-hover) / <alpha-value>)',
          foreground: 'rgb(var(--rgb-primary-foreground) / <alpha-value>)',
          soft: 'rgb(var(--rgb-primary-soft) / <alpha-value>)',
          'soft-foreground': 'rgb(var(--rgb-primary-soft-foreground) / <alpha-value>)',
        },
        success: 'rgb(var(--rgb-success) / <alpha-value>)',
        destructive: {
          DEFAULT: 'rgb(var(--rgb-destructive) / <alpha-value>)',
          foreground: 'rgb(var(--rgb-destructive-foreground) / <alpha-value>)',
          soft: 'rgb(var(--rgb-destructive-soft) / <alpha-value>)',
        },
        ring: 'rgb(var(--rgb-ring) / <alpha-value>)',
      },
      fontFamily: {
        sans: ['"Noto Sans Thai"', 'Tahoma', 'sans-serif'],
      },
      borderRadius: {
        DEFAULT: '12px',
        xl: '16px',
        '2xl': '24px',
      },
      boxShadow: {
        e1: '0 1px 2px rgb(0 0 0 / 0.3), 0 1px 3px 1px rgb(0 0 0 / 0.15)',
        e2: '0 1px 2px rgb(0 0 0 / 0.3), 0 2px 6px 2px rgb(0 0 0 / 0.15)',
        e3: '0 4px 8px 3px rgb(0 0 0 / 0.15), 0 1px 3px rgb(0 0 0 / 0.3)',
      },
      transitionDuration: {
        DEFAULT: '200ms',
      },
    },
  },
  plugins: [],
};
