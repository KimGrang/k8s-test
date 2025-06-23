import { Test, TestingModule } from '@nestjs/testing';
import { VersionController } from './version.controller';
import { VersionService } from './version.service';

describe('VersionController', () => {
  let controller: VersionController;

  beforeEach(async () => {
    const mockVersionService = {
      // VersionService의 메서드들을 mock으로 정의
      getVersion: jest.fn(),
      updateVersion: jest.fn(),
    };

    const module: TestingModule = await Test.createTestingModule({
      controllers: [VersionController],
      providers: [
        {
          provide: VersionService,
          useValue: mockVersionService,
        },
      ],
    }).compile();

    controller = module.get<VersionController>(VersionController);
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });
});
