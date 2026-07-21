/** Soil layer definitions matching the reference diagram (แผนภูมิชั้นดินเพื่อการขุดเจาะ). */

export type SoilLayerId = 'topsoil' | 'redSand' | 'ore' | 'hardpan';

export interface SoilLayer {
  id: SoilLayerId;
  nameTh: string;
  nameEn: string;
  /** Depth range from original surface (meters). */
  depthFrom: number;
  depthTo: number;
  color: string;
  hex: number;
  diggable: boolean;
  digRate: number;
  description: string;
}

/** Original surface height of the terrain plane (world Y). */
export const SURFACE_Y = 0;

/**
 * Layer depths (meters below surface).
 * Topsoil 0–1m → Red sand 1–3m → Ore (กะสะ) 3–5m → Hardpan 5m+
 */
export const SOIL_LAYERS: SoilLayer[] = [
  {
    id: 'topsoil',
    nameTh: 'ชั้นหน้าดิน',
    nameEn: 'Topsoil',
    depthFrom: 0,
    depthTo: 1,
    color: '#3d2b1f',
    hex: 0x3d2b1f,
    diggable: true,
    digRate: 1,
    description: 'ชั้นดินผิวหน้า มีหญ้าและเศษใบไม้ ต้องเปิดออกก่อนเพื่อเข้าถึงชั้นทรายแดง',
  },
  {
    id: 'redSand',
    nameTh: 'ชั้นทรายแดง',
    nameEn: 'Red Sand',
    depthFrom: 1,
    depthTo: 3,
    color: '#c45c26',
    hex: 0xc45c26,
    diggable: true,
    digRate: 1,
    description: 'ชั้นทรายสีแดงอิฐ กองแยกไว้ข้างบ่อ อย่าผสมกับแร่กะสะ',
  },
  {
    id: 'ore',
    nameTh: 'ชั้นแร่ (กะสะ)',
    nameEn: 'Ore / Kasa',
    depthFrom: 3,
    depthTo: 5,
    color: '#5a5a5a',
    hex: 0x5a5a5a,
    diggable: true,
    digRate: 0.85,
    description: 'ชั้นเป้าหมาย — กรวดและแร่กะสะ ตักขึ้นไปแต่ง/แยกแร่',
  },
  {
    id: 'hardpan',
    nameTh: 'ชั้นดินดาล',
    nameEn: 'Hardpan',
    depthFrom: 5,
    depthTo: 20,
    color: '#8a9aa8',
    hex: 0x8a9aa8,
    diggable: false,
    digRate: 0.08,
    description: 'ชั้นดินแข็ง/หิน — หยุดขุดเมื่อถึงชั้นนี้',
  },
];

export function layerAtDepth(depthMeters: number): SoilLayer {
  for (const layer of SOIL_LAYERS) {
    if (depthMeters >= layer.depthFrom && depthMeters < layer.depthTo) {
      return layer;
    }
  }
  return SOIL_LAYERS[SOIL_LAYERS.length - 1];
}

export function colorForDepth(depthMeters: number): number {
  return layerAtDepth(depthMeters).hex;
}

export interface DigStats {
  topsoil: number;
  redSand: number;
  ore: number;
  hardpan: number;
  bucketFill: number;
  /** Max fill units the bucket can hold. */
  bucketCapacity: number;
  currentLayer: SoilLayerId | null;
  currentDepth: number;
  hardpanWarning: boolean;
}

export const EMPTY_DIG_STATS: DigStats = {
  topsoil: 0,
  redSand: 0,
  ore: 0,
  hardpan: 0,
  bucketFill: 0,
  bucketCapacity: 10,
  currentLayer: null,
  currentDepth: 0,
  hardpanWarning: false,
};

export type ControlAction =
  | 'forward'
  | 'back'
  | 'turnLeft'
  | 'turnRight'
  | 'boomUp'
  | 'boomDown'
  | 'armOut'
  | 'armIn'
  | 'bucketCurl'
  | 'bucketDump'
  | 'dig'
  | 'dump';

export type ControlState = Record<ControlAction, boolean>;

export const EMPTY_CONTROLS: ControlState = {
  forward: false,
  back: false,
  turnLeft: false,
  turnRight: false,
  boomUp: false,
  boomDown: false,
  armOut: false,
  armIn: false,
  bucketCurl: false,
  bucketDump: false,
  dig: false,
  dump: false,
};
