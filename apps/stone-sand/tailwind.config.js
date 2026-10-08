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
      /** Phones in landscape. */
      short: { raw: '(max-height: 500px)' },
    },
    extend: {
      colors: {
        page: 'var(--color-page)',
        surface: 'var(--color-surface)',
        ink: 'var(--color-ink)',
        muted: 'var(--color-muted)',
        subtle: 'var(--color-subtle)',
        border: 'var(--color-border)',
        primary: {
          DEFAULT: 'var(--color-primary)',
          hover: 'var(--color-primary-hover)',
          foreground: 'var(--color-primary-foreground)',
          soft: 'var(--color-primary-soft)',
        },
        success: {
          DEFAULT: 'var(--color-success)',
          soft: 'var(--color-success-soft)',
        },
        warning: {
          DEFAULT: 'var(--color-warning)',
          soft: 'var(--color-warning-soft)',
        },
        destructive: {
          DEFAULT: 'var(--color-destructive)',
          foreground: 'var(--color-destructive-foreground)',
          soft: 'var(--color-destructive-soft)',
        },
        ring: 'var(--color-ring)',
        stamp: 'var(--color-stamp)',
      },
      fontFamily: {
        sans: ['"Noto Sans Thai"', 'Tahoma', 'sans-serif'],
      },
      borderRadius: {
        DEFAULT: '12px',
      },
      spacing: {
        'safe-top': 'env(safe-area-inset-top)',
        'safe-bottom': 'env(safe-area-inset-bottom)',
      },
      transitionDuration: {
        DEFAULT: '200ms',
      },
    },
  },
  plugins: [],
};
