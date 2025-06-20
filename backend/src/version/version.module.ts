import { Module } from '@nestjs/common';
import { VersionService } from './version.service';
import { VersionController } from './version.controller';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Version } from './entities/version.entity';
import { PushNotificationService } from '../push-notification/push-notification.service';

@Module({
  imports: [TypeOrmModule.forFeature([Version])],
  controllers: [VersionController],
  providers: [VersionService, PushNotificationService],
})
export class VersionModule {}
