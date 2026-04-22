import { useEffect, useState } from 'react';

interface BeforeInstallPromptEvent extends Event {
    prompt: () => Promise<void>;
    userChoice: Promise<{ outcome: 'accepted' | 'dismissed'; platform: string }>;
}

export const usePwaInstall = () => {
    const [deferredPrompt, setDeferredPrompt] = useState<BeforeInstallPromptEvent | null>(null);

    useEffect(() => {
        const onBeforeInstallPrompt = (event: Event) => {
            event.preventDefault();
            setDeferredPrompt(event as BeforeInstallPromptEvent);
        };
        window.addEventListener('beforeinstallprompt', onBeforeInstallPrompt);
        return () => window.removeEventListener('beforeinstallprompt', onBeforeInstallPrompt);
    }, []);

    const promptInstall = async (): Promise<boolean> => {
        if (!deferredPrompt) return false;
        await deferredPrompt.prompt();
        const choice = await deferredPrompt.userChoice;
        setDeferredPrompt(null);
        return choice.outcome === 'accepted';
    };

    return {
        canInstall: !!deferredPrompt,
        promptInstall,
    };
};
