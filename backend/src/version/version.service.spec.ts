import { Test, TestingModule } from '@nestjs/testing';
import { VersionService } from './version.service';
import { PushNotificationService } from '../push-notification/push-notification.service';

describe('VersionService', () => {
  let service: VersionService;

  beforeEach(async () => {
    const mockVersionRepository = {
      // Repository 메서드들을 mock으로 정의
      findOne: jest.fn(),
      save: jest.fn(),
      create: jest.fn(),
    };

    const mockPushNotificationService = {
      // PushNotificationService 메서드들을 mock으로 정의
      sendNotification: jest.fn(),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        VersionService,
        {
          provide: 'VersionRepository', // 정확한 토큰 이름 확인 필요
          useValue: mockVersionRepository,
        },
        {
          provide: PushNotificationService,
          useValue: mockPushNotificationService,
        },
      ],
    }).compile();

    service = module.get<VersionService>(VersionService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });
});
