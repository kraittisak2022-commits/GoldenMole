import { AdminLog, AdminUser, AppSettings, Employee, LandProject, Transaction } from '../types';

export type BackupFrequency = 'daily' | 'monthly';

interface SnapshotPayload {
    employees: Employee[];
    transactions: Transaction[];
    projects: LandProject[];
    settings: AppSettings;
    admins: AdminUser[];
    adminLogs: AdminLog[];
}

export interface BackupRunResult {
    ok: boolean;
    fileName: string;
    error?: string;
    driveFileId?: string;
    driveWebViewLink?: string;
}

export const isBackupDue = (frequency: BackupFrequency, lastBackupAt?: string): boolean => {
    if (!lastBackupAt) return true;
    const last = new Date(lastBackupAt);
    if (Number.isNaN(last.getTime())) return true;
    const now = new Date();
    if (frequency === 'daily') {
        return now.toDateString() !== last.toDateString();
    }
    return now.getFullYear() !== last.getFullYear() || now.getMonth() !== last.getMonth();
};

export const buildBackupFileName = (prefix: string | undefined, mode: 'manual' | 'auto') => {
    const safePrefix = (prefix || 'backup').trim().replace(/[^a-zA-Z0-9ก-๙_-]+/g, '_').slice(0, 40) || 'backup';
    const stamp = new Date().toISOString().replace(/[:.]/g, '-');
    return `${safePrefix}_${mode}_${stamp}.json`;
};

export const buildSnapshotJson = (
    payload: SnapshotPayload,
    options?: { includeSettings?: boolean; includeDatabase?: boolean }
) => {
    const includeSettings = options?.includeSettings ?? true;
    const includeDatabase = options?.includeDatabase ?? true;
    return JSON.stringify(
        {
            meta: {
                schemaVersion: 1,
                generatedAt: new Date().toISOString(),
                timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || 'Asia/Bangkok',
            },
            settings: includeSettings ? payload.settings : undefined,
            database: includeDatabase
                ? {
                      employees: payload.employees,
                      transactions: payload.transactions,
                      projects: payload.projects,
                      admins: payload.admins,
                      adminLogs: payload.adminLogs,
                  }
                : undefined,
        },
        null,
        2
    );
};

const uploadToGoogleDrive = async (args: {
    accessToken: string;
    folderId?: string;
    fileName: string;
    content: string;
}) => {
    const boundary = `backup_${Date.now()}`;
    const metadata: Record<string, unknown> = { name: args.fileName, mimeType: 'application/json' };
    if (args.folderId?.trim()) metadata.parents = [args.folderId.trim()];

    const body =
        `--${boundary}\r\n` +
        'Content-Type: application/json; charset=UTF-8\r\n\r\n' +
        `${JSON.stringify(metadata)}\r\n` +
        `--${boundary}\r\n` +
        'Content-Type: application/json\r\n\r\n' +
        `${args.content}\r\n` +
        `--${boundary}--`;

    const response = await fetch('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,webViewLink', {
        method: 'POST',
        headers: {
            Authorization: `Bearer ${args.accessToken}`,
            'Content-Type': `multipart/related; boundary=${boundary}`,
        },
        body,
    });

    if (!response.ok) {
        const errorText = await response.text();
        throw new Error(errorText || `Google Drive upload failed (${response.status})`);
    }
    return response.json() as Promise<{ id: string; webViewLink?: string }>;
};

export const runBackup = async (args: {
    payload: SnapshotPayload;
    mode: 'manual' | 'auto';
    backupName?: string;
    includeSettings?: boolean;
    includeDatabase?: boolean;
    googleDrive?: {
        autoUpload?: boolean;
        folderId?: string;
        accessToken?: string;
    };
}): Promise<BackupRunResult> => {
    const fileName = buildBackupFileName(args.backupName, args.mode);
    const content = buildSnapshotJson(args.payload, {
        includeSettings: args.includeSettings,
        includeDatabase: args.includeDatabase,
    });

    try {
        if (args.googleDrive?.autoUpload) {
            const token = args.googleDrive.accessToken?.trim();
            if (!token) {
                return { ok: false, fileName, error: 'ยังไม่ได้ตั้งค่า Google Drive Access Token' };
            }
            const uploaded = await uploadToGoogleDrive({
                accessToken: token,
                folderId: args.googleDrive.folderId,
                fileName,
                content,
            });
            return { ok: true, fileName, driveFileId: uploaded.id, driveWebViewLink: uploaded.webViewLink };
        }

        // fallback: download to local device
        const blob = new Blob([content], { type: 'application/json' });
        const href = URL.createObjectURL(blob);
        const anchor = document.createElement('a');
        anchor.href = href;
        anchor.download = fileName;
        document.body.appendChild(anchor);
        anchor.click();
        anchor.remove();
        URL.revokeObjectURL(href);
        return { ok: true, fileName };
    } catch (e: any) {
        return { ok: false, fileName, error: e?.message || 'backup failed' };
    }
};
