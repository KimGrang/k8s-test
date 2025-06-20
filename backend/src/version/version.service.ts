// src/version/version.service.ts
import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Version } from './entities/version.entity';
import { PushNotificationService } from '../push-notification/push-notification.service';

@Injectable()
export class VersionService {
  constructor(
    @InjectRepository(Version)
    private versionRepository: Repository<Version>,
    private pushNotificationService: PushNotificationService,
  ) {}

  async getCurrentVersion() {
    const version = await this.versionRepository.findOne({
      where: { isActive: true },
      order: { createdAt: 'DESC' },
    });

    return {
      version: version?.version || '1.0.0',
      timestamp: version?.createdAt || new Date(),
      forceUpdate: version?.forceUpdate || false,
    };
  }

  async updateVersion(version: string, timestamp: string) {
    // 기존 활성 버전 비활성화
    await this.versionRepository.update(
      { isActive: true },
      { isActive: false },
    );

    // 새 버전 생성
    const newVersion = this.versionRepository.create({
      version,
      timestamp: new Date(timestamp),
      isActive: true,
      forceUpdate: false,
    });

    const savedVersion = await this.versionRepository.save(newVersion);

    // 모든 클라이언트에게 업데이트 알림 전송
    // await this.pushNotificationService.notifyAllClients({
    //   type: 'VERSION_UPDATE',
    //   version: version,
    //   forceUpdate: false,
    // });

    return savedVersion;
  }

  async checkForUpdates(platform: string, currentVersion: string) {
    const latestVersion = await this.getCurrentVersion();

    const needsUpdate =
      this.compareVersions(currentVersion, latestVersion.version) < 0;

    return {
      needsUpdate,
      latestVersion: latestVersion.version,
      forceUpdate: latestVersion.forceUpdate,
      downloadUrl: this.getDownloadUrl(platform),
      updateMessage: needsUpdate
        ? 'New version available!'
        : 'You have the latest version',
    };
  }

  private compareVersions(version1: string, version2: string): number {
    const v1parts = version1.split('.').map(Number);
    const v2parts = version2.split('.').map(Number);

    for (let i = 0; i < Math.max(v1parts.length, v2parts.length); i++) {
      const v1part = v1parts[i] || 0;
      const v2part = v2parts[i] || 0;

      if (v1part < v2part) return -1;
      if (v1part > v2part) return 1;
    }

    return 0;
  }

  private getDownloadUrl(platform: string): string {
    const urls: { [key: string]: string } = {
      ios: 'https://apps.apple.com/app/your-app',
      android: 'https://play.google.com/store/apps/details?id=your.app',
    };

    return urls[platform.toLowerCase()] || '';
  }
}
