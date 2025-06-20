import { Controller, Get, Post, Body, Param } from '@nestjs/common';
import { VersionService } from './version.service';

@Controller('api/version')
export class VersionController {
  constructor(private readonly versionService: VersionService) {}

  @Get()
  async getCurrentVersion() {
    return this.versionService.getCurrentVersion();
  }

  @Post('update')
  async updateVersion(
    @Body() updateData: { version: string; timestamp: string },
  ) {
    return this.versionService.updateVersion(
      updateData.version,
      updateData.timestamp,
    );
  }

  @Get('check/:platform/:currentVersion')
  async checkForUpdates(
    @Param('platform') platform: string,
    @Param('currentVersion') currentVersion: string,
  ) {
    return this.versionService.checkForUpdates(platform, currentVersion);
  }
}
