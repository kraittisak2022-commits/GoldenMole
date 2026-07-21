import { useCallback, useEffect, useRef, useState } from 'react';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import ControlPad from './ControlPad';
import {
  EMPTY_CONTROLS,
  EMPTY_DIG_STATS,
  SURFACE_Y,
  colorForDepth,
  layerAtDepth,
  type ControlState,
  type DigStats,
  type SoilLayerId,
} from './soilLayers';

const TERRAIN_SIZE = 40;
const TERRAIN_SEGMENTS = 96;
const HALF = TERRAIN_SIZE / 2;

/** Kobelco-like teal. */
const BODY_COLOR = 0x1a8a8a;
const METAL_COLOR = 0x2a2a2a;
const TRACK_COLOR = 0x1a1a1a;

interface ExcavatorParts {
  root: THREE.Group;
  cabin: THREE.Group;
  boom: THREE.Group;
  arm: THREE.Group;
  bucket: THREE.Group;
  bucketTip: THREE.Object3D;
}

function createExcavator(): ExcavatorParts {
  const root = new THREE.Group();
  root.position.set(8, SURFACE_Y, 4);

  const bodyMat = new THREE.MeshStandardMaterial({
    color: BODY_COLOR,
    metalness: 0.35,
    roughness: 0.55,
  });
  const metalMat = new THREE.MeshStandardMaterial({
    color: METAL_COLOR,
    metalness: 0.6,
    roughness: 0.4,
  });
  const trackMat = new THREE.MeshStandardMaterial({
    color: TRACK_COLOR,
    metalness: 0.2,
    roughness: 0.85,
  });

  // Tracks / undercarriage
  const undercarriage = new THREE.Group();
  const chassis = new THREE.Mesh(new THREE.BoxGeometry(2.4, 0.45, 1.5), metalMat);
  chassis.position.y = 0.35;
  chassis.castShadow = true;
  undercarriage.add(chassis);

  for (const z of [-0.7, 0.7]) {
    const track = new THREE.Mesh(new THREE.BoxGeometry(2.6, 0.4, 0.45), trackMat);
    track.position.set(0, 0.2, z);
    track.castShadow = true;
    undercarriage.add(track);
  }
  root.add(undercarriage);

  // Rotating cabin / house
  const cabin = new THREE.Group();
  cabin.position.y = 0.7;
  root.add(cabin);

  const house = new THREE.Mesh(new THREE.BoxGeometry(1.8, 1.0, 1.4), bodyMat);
  house.position.set(-0.15, 0.55, 0);
  house.castShadow = true;
  cabin.add(house);

  const cabGlass = new THREE.Mesh(
    new THREE.BoxGeometry(0.7, 0.55, 0.9),
    new THREE.MeshStandardMaterial({
      color: 0x88ccee,
      metalness: 0.1,
      roughness: 0.2,
      transparent: true,
      opacity: 0.7,
    }),
  );
  cabGlass.position.set(0.55, 0.7, 0);
  cabin.add(cabGlass);

  const counterweight = new THREE.Mesh(new THREE.BoxGeometry(0.7, 0.7, 1.3), bodyMat);
  counterweight.position.set(-1.15, 0.4, 0);
  cabin.add(counterweight);

  // Boom pivot
  const boom = new THREE.Group();
  boom.position.set(0.9, 0.85, 0);
  cabin.add(boom);

  const boomMesh = new THREE.Mesh(new THREE.BoxGeometry(0.35, 0.35, 3.2), bodyMat);
  boomMesh.rotation.x = Math.PI / 2;
  boomMesh.position.set(0, 0, -1.5);
  boomMesh.castShadow = true;
  boom.add(boomMesh);

  // Arm
  const arm = new THREE.Group();
  arm.position.set(0, 0, -3.1);
  boom.add(arm);

  const armMesh = new THREE.Mesh(new THREE.BoxGeometry(0.28, 0.28, 2.2), bodyMat);
  armMesh.rotation.x = Math.PI / 2;
  armMesh.position.set(0, 0, -1.0);
  armMesh.castShadow = true;
  arm.add(armMesh);

  // Bucket
  const bucket = new THREE.Group();
  bucket.position.set(0, 0, -2.15);
  arm.add(bucket);

  const bucketBody = new THREE.Mesh(new THREE.BoxGeometry(0.85, 0.55, 0.7), metalMat);
  bucketBody.position.set(0, -0.15, -0.15);
  bucketBody.castShadow = true;
  bucket.add(bucketBody);

  // Teeth
  for (let i = -1; i <= 1; i++) {
    const tooth = new THREE.Mesh(new THREE.ConeGeometry(0.06, 0.22, 4), metalMat);
    tooth.rotation.x = Math.PI;
    tooth.position.set(i * 0.28, -0.42, -0.35);
    bucket.add(tooth);
  }

  const bucketTip = new THREE.Object3D();
  bucketTip.position.set(0, -0.5, -0.45);
  bucket.add(bucketTip);

  // Default joint angles (radians)
  boom.rotation.x = -0.55;
  arm.rotation.x = 0.9;
  bucket.rotation.x = 0.4;

  return { root, cabin, boom, arm, bucket, bucketTip };
}

function buildTerrain(): {
  mesh: THREE.Mesh;
  geometry: THREE.PlaneGeometry;
  heights: Float32Array;
} {
  const geometry = new THREE.PlaneGeometry(
    TERRAIN_SIZE,
    TERRAIN_SIZE,
    TERRAIN_SEGMENTS,
    TERRAIN_SEGMENTS,
  );
  geometry.rotateX(-Math.PI / 2);

  const pos = geometry.attributes.position as THREE.BufferAttribute;
  const count = pos.count;
  const heights = new Float32Array(count);
  const colors = new Float32Array(count * 3);
  const color = new THREE.Color();

  for (let i = 0; i < count; i++) {
    const x = pos.getX(i);
    const z = pos.getZ(i);
    // Gentle natural undulation + flat work area near origin
    const undulation =
      Math.sin(x * 0.15) * 0.15 + Math.cos(z * 0.12) * 0.12 + Math.sin((x + z) * 0.08) * 0.08;
    const dist = Math.sqrt(x * x + z * z);
    const flatten = THREE.MathUtils.smoothstep(dist, 4, 14);
    const h = SURFACE_Y + undulation * flatten;
    pos.setY(i, h);
    heights[i] = h;

    // Color by depth relative to surface (initially all topsoil)
    color.setHex(colorForDepth(0));
    colors[i * 3] = color.r;
    colors[i * 3 + 1] = color.g;
    colors[i * 3 + 2] = color.b;
  }

  geometry.setAttribute('color', new THREE.BufferAttribute(colors, 3));
  geometry.computeVertexNormals();

  const material = new THREE.MeshStandardMaterial({
    vertexColors: true,
    roughness: 0.95,
    metalness: 0.05,
    flatShading: false,
  });

  const mesh = new THREE.Mesh(geometry, material);
  mesh.receiveShadow = true;
  mesh.castShadow = false;

  return { mesh, geometry, heights };
}

function heightAt(
  heights: Float32Array,
  worldX: number,
  worldZ: number,
): number {
  const u = (worldX + HALF) / TERRAIN_SIZE;
  const v = (worldZ + HALF) / TERRAIN_SIZE;
  if (u < 0 || u > 1 || v < 0 || v > 1) return SURFACE_Y;

  const gx = u * TERRAIN_SEGMENTS;
  const gz = v * TERRAIN_SEGMENTS;
  const ix = Math.floor(gx);
  const iz = Math.floor(gz);
  const fx = gx - ix;
  const fz = gz - iz;

  const idx = (x: number, z: number) => {
    const cx = Math.min(TERRAIN_SEGMENTS, Math.max(0, x));
    const cz = Math.min(TERRAIN_SEGMENTS, Math.max(0, z));
    // PlaneGeometry vertices: row-major along width (x), then depth (z after rotate)
    return cz * (TERRAIN_SEGMENTS + 1) + cx;
  };

  const h00 = heights[idx(ix, iz)];
  const h10 = heights[idx(ix + 1, iz)];
  const h01 = heights[idx(ix, iz + 1)];
  const h11 = heights[idx(ix + 1, iz + 1)];
  const h0 = h00 * (1 - fx) + h10 * fx;
  const h1 = h01 * (1 - fx) + h11 * fx;
  return h0 * (1 - fz) + h1 * fz;
}

export default function MiningSimulation3D() {
  const containerRef = useRef<HTMLDivElement>(null);
  const canvasHostRef = useRef<HTMLDivElement>(null);
  const controlsRef = useRef<ControlState>({ ...EMPTY_CONTROLS });
  const digStatsRef = useRef<DigStats>({ ...EMPTY_DIG_STATS });
  const [digStats, setDigStats] = useState<DigStats>({ ...EMPTY_DIG_STATS });

  const onControlsChange = useCallback((c: ControlState) => {
    controlsRef.current = c;
  }, []);

  useEffect(() => {
    const host = canvasHostRef.current;
    if (!host) return;

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x87b8e0);
    scene.fog = new THREE.Fog(0x87b8e0, 35, 90);

    const camera = new THREE.PerspectiveCamera(
      50,
      host.clientWidth / Math.max(1, host.clientHeight),
      0.1,
      200,
    );
    camera.position.set(16, 12, 16);

    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setSize(host.clientWidth, host.clientHeight);
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    host.appendChild(renderer.domElement);

    const orbit = new OrbitControls(camera, renderer.domElement);
    orbit.enableDamping = true;
    orbit.dampingFactor = 0.08;
    orbit.maxPolarAngle = Math.PI * 0.48;
    orbit.minDistance = 6;
    orbit.maxDistance = 45;
    orbit.target.set(4, 0, 2);

    // Lights
    const hemi = new THREE.HemisphereLight(0xfff5e0, 0x4a3a2a, 0.55);
    scene.add(hemi);
    const sun = new THREE.DirectionalLight(0xfff0d0, 1.15);
    sun.position.set(20, 30, 10);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    sun.shadow.camera.near = 1;
    sun.shadow.camera.far = 80;
    sun.shadow.camera.left = -30;
    sun.shadow.camera.right = 30;
    sun.shadow.camera.top = 30;
    sun.shadow.camera.bottom = -30;
    scene.add(sun);

    // Terrain
    const { mesh: terrain, geometry, heights } = buildTerrain();
    scene.add(terrain);

    // Simple sky bushes / distant ground strip
    const groundMat = new THREE.MeshStandardMaterial({ color: 0x6b8f4e, roughness: 1 });
    const farGround = new THREE.Mesh(new THREE.PlaneGeometry(120, 120), groundMat);
    farGround.rotation.x = -Math.PI / 2;
    farGround.position.y = SURFACE_Y - 0.05;
    farGround.receiveShadow = true;
    scene.add(farGround);
    // Keep diggable terrain on top
    terrain.position.y = 0.02;

    // Excavator
    const excavator = createExcavator();
    scene.add(excavator.root);

    // Dump pile group
    const dumpPiles = new THREE.Group();
    scene.add(dumpPiles);
    let dumpIndex = 0;
    let dumpWasHeld = false;

    // Bucket fill visual
    const fillMesh = new THREE.Mesh(
      new THREE.SphereGeometry(0.25, 8, 8),
      new THREE.MeshStandardMaterial({ color: 0x5a5a5a }),
    );
    fillMesh.visible = false;
    excavator.bucket.add(fillMesh);
    fillMesh.position.set(0, -0.05, -0.1);

    const tipWorld = new THREE.Vector3();
    const clock = new THREE.Clock();
    let raf = 0;
    let disposed = false;
    let statsDirty = false;
    let lastStatsPush = 0;

    const pushStats = () => {
      setDigStats({ ...digStatsRef.current });
      statsDirty = false;
    };

    const digAt = (wx: number, wz: number, dt: number) => {
      const radius = 0.85;
      const pos = geometry.attributes.position as THREE.BufferAttribute;
      const col = geometry.attributes.color as THREE.BufferAttribute;
      const color = new THREE.Color();
      let dug = 0;
      let layerId: SoilLayerId | null = null;
      let maxDepth = 0;
      let hitHardpan = false;

      const bucketDepth = Math.max(0, SURFACE_Y - tipWorld.y + 0.15);
      const layer = layerAtDepth(bucketDepth);
      layerId = layer.id;
      maxDepth = bucketDepth;

      if (!layer.diggable && digStatsRef.current.bucketFill >= digStatsRef.current.bucketCapacity * 0.05) {
        hitHardpan = true;
      }

      const digAmount = 0.9 * dt * layer.digRate;
      if (digStatsRef.current.bucketFill >= digStatsRef.current.bucketCapacity) {
        digStatsRef.current.currentLayer = layerId;
        digStatsRef.current.currentDepth = maxDepth;
        digStatsRef.current.hardpanWarning = layer.id === 'hardpan';
        statsDirty = true;
        return;
      }

      for (let i = 0; i < pos.count; i++) {
        const x = pos.getX(i);
        const z = pos.getZ(i);
        const dx = x - wx;
        const dz = z - wz;
        const dist = Math.sqrt(dx * dx + dz * dz);
        if (dist > radius) continue;

        const falloff = 1 - dist / radius;
        const currentY = heights[i];
        const depth = SURFACE_Y - currentY;
        const vertLayer = layerAtDepth(Math.max(0, depth));
        const rate = vertLayer.digRate;
        const delta = digAmount * falloff * falloff * rate;

        // Soft floor: hardpan resists strongly; stop near hardpan surface
        const minY = SURFACE_Y - 5.15;
        const newY = Math.max(minY, currentY - delta);
        if (newY >= currentY - 1e-5) {
          if (vertLayer.id === 'hardpan') hitHardpan = true;
          continue;
        }

        const removed = currentY - newY;
        dug += removed;
        heights[i] = newY;
        pos.setY(i, newY);

        const newDepth = SURFACE_Y - newY;
        color.setHex(colorForDepth(newDepth));
        col.setXYZ(i, color.r, color.g, color.b);

        digStatsRef.current[vertLayer.id] += removed * 0.35;
        if (vertLayer.id === 'hardpan') hitHardpan = true;
      }

      if (dug > 0) {
        geometry.attributes.position.needsUpdate = true;
        geometry.attributes.color.needsUpdate = true;
        geometry.computeVertexNormals();
        digStatsRef.current.bucketFill = Math.min(
          digStatsRef.current.bucketCapacity,
          digStatsRef.current.bucketFill + dug * 0.5,
        );
      }

      digStatsRef.current.currentLayer = layerId;
      digStatsRef.current.currentDepth = maxDepth;
      digStatsRef.current.hardpanWarning = hitHardpan || layer.id === 'hardpan';
      statsDirty = true;
    };

    const doDump = () => {
      const fill = digStatsRef.current.bucketFill;
      if (fill < 0.15) return;

      excavator.root.updateMatrixWorld(true);
      const dumpPos = new THREE.Vector3(1.5, 0.3, -2.2);
      excavator.root.localToWorld(dumpPos);

      // Prefer ore color if mostly ore dug recently
      const oreShare =
        digStatsRef.current.ore /
        Math.max(
          0.01,
          digStatsRef.current.topsoil +
            digStatsRef.current.redSand +
            digStatsRef.current.ore +
            digStatsRef.current.hardpan,
        );
      const pileColor =
        oreShare > 0.35 ? 0x5a5a5a : digStatsRef.current.redSand > digStatsRef.current.topsoil ? 0xc45c26 : 0x3d2b1f;

      const pile = new THREE.Mesh(
        new THREE.ConeGeometry(0.4 + fill * 0.04, 0.35 + fill * 0.06, 8),
        new THREE.MeshStandardMaterial({ color: pileColor, roughness: 1 }),
      );
      const groundY = heightAt(heights, dumpPos.x, dumpPos.z);
      pile.position.set(
        dumpPos.x + (dumpIndex % 5) * 0.35,
        groundY + 0.2,
        dumpPos.z + Math.floor(dumpIndex / 5) * 0.35,
      );
      pile.castShadow = true;
      dumpPiles.add(pile);
      dumpIndex += 1;

      digStatsRef.current.bucketFill = 0;
      statsDirty = true;
    };

    // Place excavator on terrain
    const syncExcavatorHeight = () => {
      const h = heightAt(
        heights,
        excavator.root.position.x,
        excavator.root.position.z,
      );
      excavator.root.position.y = h;
    };
    syncExcavatorHeight();

    const animate = () => {
      if (disposed) return;
      raf = requestAnimationFrame(animate);
      const dt = Math.min(clock.getDelta(), 0.05);
      const c = controlsRef.current;

      // Drive
      const turnSpeed = 1.4;
      const moveSpeed = 3.2;
      if (c.turnLeft) excavator.root.rotation.y += turnSpeed * dt;
      if (c.turnRight) excavator.root.rotation.y -= turnSpeed * dt;

      if (c.forward || c.back) {
        const dir = c.forward ? 1 : -1;
        excavator.root.position.x += Math.sin(excavator.root.rotation.y) * moveSpeed * dt * dir;
        excavator.root.position.z += Math.cos(excavator.root.rotation.y) * moveSpeed * dt * dir;
        // Clamp to terrain
        excavator.root.position.x = THREE.MathUtils.clamp(
          excavator.root.position.x,
          -HALF + 2,
          HALF - 2,
        );
        excavator.root.position.z = THREE.MathUtils.clamp(
          excavator.root.position.z,
          -HALF + 2,
          HALF - 2,
        );
        syncExcavatorHeight();
      }

      // Arm joints
      const jointSpeed = 0.9;
      if (c.boomUp) excavator.boom.rotation.x = Math.min(-0.15, excavator.boom.rotation.x + jointSpeed * dt);
      if (c.boomDown) excavator.boom.rotation.x = Math.max(-1.2, excavator.boom.rotation.x - jointSpeed * dt);
      if (c.armOut) excavator.arm.rotation.x = Math.min(1.6, excavator.arm.rotation.x + jointSpeed * dt);
      if (c.armIn) excavator.arm.rotation.x = Math.max(0.2, excavator.arm.rotation.x - jointSpeed * dt);
      if (c.bucketCurl) excavator.bucket.rotation.x = Math.min(1.2, excavator.bucket.rotation.x + jointSpeed * 1.2 * dt);
      if (c.bucketDump) excavator.bucket.rotation.x = Math.max(-0.4, excavator.bucket.rotation.x - jointSpeed * 1.2 * dt);

      excavator.root.updateMatrixWorld(true);
      excavator.bucketTip.getWorldPosition(tipWorld);

      // Probe layer under tip for HUD even when not digging
      const tipDepth = Math.max(0, SURFACE_Y - tipWorld.y);
      const tipLayer = layerAtDepth(tipDepth);
      if (
        digStatsRef.current.currentLayer !== tipLayer.id ||
        Math.abs(digStatsRef.current.currentDepth - tipDepth) > 0.05
      ) {
        digStatsRef.current.currentLayer = tipLayer.id;
        digStatsRef.current.currentDepth = tipDepth;
        statsDirty = true;
      }

      if (c.dig) {
        digAt(tipWorld.x, tipWorld.z, dt);
      }
      if (c.dump && !dumpWasHeld) {
        doDump();
      }
      dumpWasHeld = c.dump;

      // Bucket fill visual
      const fillRatio = digStatsRef.current.bucketFill / digStatsRef.current.bucketCapacity;
      fillMesh.visible = fillRatio > 0.05;
      fillMesh.scale.setScalar(0.5 + fillRatio * 1.2);
      if (fillRatio > 0.4) {
        (fillMesh.material as THREE.MeshStandardMaterial).color.setHex(0x5a5a5a);
      } else if (digStatsRef.current.redSand > digStatsRef.current.topsoil) {
        (fillMesh.material as THREE.MeshStandardMaterial).color.setHex(0xc45c26);
      } else {
        (fillMesh.material as THREE.MeshStandardMaterial).color.setHex(0x3d2b1f);
      }

      // Soft camera follow when driving
      if (c.forward || c.back || c.turnLeft || c.turnRight) {
        orbit.target.lerp(
          new THREE.Vector3(
            excavator.root.position.x,
            excavator.root.position.y + 1,
            excavator.root.position.z,
          ),
          0.04,
        );
      }

      orbit.update();
      renderer.render(scene, camera);

      const now = performance.now();
      if (statsDirty && now - lastStatsPush > 100) {
        lastStatsPush = now;
        pushStats();
      }
    };
    animate();

    const onResize = () => {
      if (!host) return;
      const w = host.clientWidth;
      const h = Math.max(1, host.clientHeight);
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
      renderer.setSize(w, h);
    };
    const ro = new ResizeObserver(onResize);
    ro.observe(host);

    return () => {
      disposed = true;
      cancelAnimationFrame(raf);
      ro.disconnect();
      orbit.dispose();
      renderer.dispose();
      geometry.dispose();
      (terrain.material as THREE.Material).dispose();
      if (renderer.domElement.parentElement === host) {
        host.removeChild(renderer.domElement);
      }
    };
  }, []);

  return (
    <div
      ref={containerRef}
      className="relative w-full h-[min(70vh,640px)] min-h-[360px] rounded-2xl overflow-hidden border border-slate-300 dark:border-slate-600 shadow-xl bg-slate-900"
    >
      <div ref={canvasHostRef} className="absolute inset-0" />
      <ControlPad digStats={digStats} onControlsChange={onControlsChange} />
    </div>
  );
}
