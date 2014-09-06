part of Dark;

class PlayerSpawn {
  Vector3 pos;
  double rot;
  
  PlayerSpawn(this.pos, this.rot);
}

class EntityBlockerType {
  static const NONE = const EntityBlockerType._(0);
  static const BLOCKING = const EntityBlockerType._(1);
  static const PICKUP = const EntityBlockerType._(2);

  final int type;
  const EntityBlockerType._(this.type);
}

class Entity {
  Level level;
  Vector3 pos;
  double radius = 16.0;
  double height = 56.0;
  double rot = 0.0;
  SpriteTemplate spriteTemplate;
  bool transparent = false;
  int animFrame = 0;
  bool hanging = false;
  bool shouldAimAt = false;
  bool bleeds = false;
  List<SubSector> inSubSectors = new List<SubSector>();
  bool removed = false;
  bool collided = false;
  
  
  EntityBlockerType blockerType = EntityBlockerType.BLOCKING;
//  bool blocking = false;
// bool pickup = false;
  
  BlockCell blockCell;
  
  Entity(this.level, this.pos, this.blockerType) {
    level.bsp.findSubSectorsInRadius(pos.x, pos.z, 0.0, inSubSectors);

    if (blockerType!=EntityBlockerType.NONE) {
      blockCell = level.blockmap.getBlockCell(pos.x, pos.z);
      if (blockCell!=null) {
        if (blockerType==EntityBlockerType.BLOCKING) blockCell.blockers.add(this);
        if (blockerType==EntityBlockerType.PICKUP) blockCell.pickups.add(this);
      }
    }
  }
  
  void tick(double passedTime) {
  }
  
  void addToDisplayList(double playerRot) {
    if (spriteTemplate==null) return;
    Sector sector = level.bsp.findSector(pos.xz);
    
    double rotDiff = rot - playerRot+PI;
    int rotFrame = (rotDiff * 8 / (PI * 2) + 0.5).floor() & 7;
    SpriteTemplateFrame stf = spriteTemplate.frames[animFrame];
    if (stf.rots.length == 1) rotFrame = 0;
    SpriteTemplateRot str = stf.rots[rotFrame];

    int closestSubSectorId = inSubSectors[0].sortedSubSectorId;
    for (int i=1; i<inSubSectors.length; i++) {
      if (closestSubSectorId>inSubSectors[i].sortedSubSectorId) closestSubSectorId = inSubSectors[i].sortedSubSectorId;
    }
    
    if (transparent) {
      renderers.transparentSpriteMaps[str.image.imageAtlas.texture].insertSprite(sector, pos, closestSubSectorId, str);
    } else {
      renderers.spriteMaps[str.image.imageAtlas.texture].insertSprite(sector, pos, closestSubSectorId, str);
    }
  }
  
  void remove() {
    if (blockerType==EntityBlockerType.BLOCKING) {
      if (blockCell!=null) blockCell.blockers.remove(this);
    } else if (blockerType==EntityBlockerType.PICKUP) {
      if (blockCell!=null) blockCell.pickups.remove(this);
    }
    
    removed = true;
  }
  
  static int checkCounterHack = 0;
  static List<BlockCell> tmpBlockCells = new List<BlockCell>();
  static Set<Wall> tmpLinedefs = new Set<Wall>();

  void clipMove(Vector3 motion, double passedTime, HashSet<Sector> sectorsInRange) {
    int steps = (motion.length/(radius/3.0)).floor()+1;
    
    for (int i=0; i<steps; i++) {
      checkCounterHack++;
      pos.x+=motion.x*(passedTime/steps);
      pos.z+=motion.z*(passedTime/steps);

      level.blockmap.getBlockCellsRadius(pos.x, pos.z, radius+64.0, tmpBlockCells);
      for (int i=0; i<tmpBlockCells.length; i++) {
        collideAgainstEntitiesIn(tmpBlockCells[i]);
      }

      inSubSectors.clear();
      level.bsp.findSubSectorsInRadius(pos.x, pos.z, radius, inSubSectors);
      for (int i=0; i<inSubSectors.length; i++) {
        SubSector ss = inSubSectors[i];
        for (int j=0; j<ss.walls.length; j++) {
          Wall ld = ss.walls[j];
          if (ld.checkCounterHack != checkCounterHack) {
            ld.checkCounterHack = checkCounterHack;
            clipMotion(ld, sectorsInRange);
          }
        }
      }
    }
  }
  

  void collideAgainstEntitiesIn(BlockCell bc) {
    for (int j=0; j<bc.blockers.length; j++) {
      Entity e = bc.blockers[j];
      if (e!=this) clipMotionEntity(e);
    }
  }
  
  bool canEnterSector(Sector sector) {
    if (sector.floorHeight>pos.y+24) return false;
    if (sector.ceilingHeight-sector.floorHeight==0) return true;
    if (sector.ceilingHeight-sector.floorHeight<height) return false;
    return true;
  }
  
  void clipMotionEntity(Entity e) {
    double xd = pos.x-e.pos.x;
    double yd = pos.z-e.pos.z;
    double len2 = xd*xd+yd*yd;
    double sRad = radius+e.radius;
    if (len2>0.01 && len2<sRad*sRad) {
      double len = sqrt(len2);
      double toPushout = sRad-len;
      pos.x+=xd/len*toPushout;
      pos.z+=yd/len*toPushout;
      collided = true;
    }
  }
  
  bool clipMotion(Wall seg, HashSet<Sector> overlappedSectors) {
    double xp = pos.x;
    double yp = pos.z;

    double xNudge = 0.0;
    double yNudge = 0.0;
    bool intersect = false;

    double d = xp*seg.xn+yp*seg.yn - seg.d;
    double mul = 1.0;
    if (d>=-radius && d<=radius) {
      if (d<0) {
        d=-d;
        mul = -1.0;
      }
      double sd = xp*seg.xt+yp*seg.yt - seg.sd;
      if (sd>=0.0 && sd<=seg.length) {
        // Hit the center of the seg
        double toPushOut = radius-d+0.001;
        xNudge=seg.xn*toPushOut*mul;
        yNudge=seg.yn*toPushOut*mul;
        intersect = true;
      } else {
        // Hit either corner of the linedef
        double xd, yd;
        if (sd<=0.0) {
          xd = xp-seg.x0;
          yd = yp-seg.y0;
        } else {
          xd = xp-seg.x1;
          yd = yp-seg.y1;
        }

        double distSqr = xd*xd+yd*yd;
        if (xd*xd+yd*yd<radius*radius) {
          double dist = sqrt(distSqr);
          double toPushOut = radius-dist+0.001;
          xNudge=xd/dist*toPushOut;
          yNudge=yd/dist*toPushOut;
          intersect = true;
        }
      }
    }

    if (intersect) {
      bool collideWall = false;
      if (seg.data.impassable || seg.leftSector==null) {
        collideWall = true;
      } else if (!canEnterSector(seg.leftSector) || !canEnterSector(seg.rightSector)) {
        collideWall = true;
      }

      if (collideWall) {
        collided = true;
        pos.x += xNudge;
        pos.z += yNudge;
        return true;
      } else if (overlappedSectors!=null) {
        overlappedSectors.add(seg.rightSector);
        if (seg.leftSector!=null) overlappedSectors.add(seg.leftSector);
        return false;
      }
    }
    return false;
  }  
}

class AnimatedStationary extends Entity {
  String frames;
  int animStep = 0;
  double animAccum = 0.0;
  
  AnimatedStationary(String templateName, String frames, Level level, Vector3 pos, double rot, EntityBlockerType blockerType) : super(level, pos, blockerType) {
    frames = frames.toUpperCase();
    this.frames = frames;
    spriteTemplate = spriteTemplates[templateName];
    this.pos = pos;
    this.rot = rot;
    animFrame = FRAME_NAMES.indexOf(frames.substring(animStep, animStep+1));
    radius = 16.0;
  }
  
  void tick(double passedTime) {
    int lastAnimStep = animStep;
    animAccum+=passedTime*35.0/6.0;
    animStep+=animAccum.floor();
    animAccum-=animAccum.floor();
    animStep = animStep%frames.length;
    if (lastAnimStep!=animStep) {
      animFrame = FRAME_NAMES.indexOf(frames.substring(animStep, animStep+1));
    }
  }
}

class Pickup extends AnimatedStationary {
  Pickup(String templateName, String frames, Level level, Vector3 pos, double rot) : super(templateName, frames, level, pos, rot, EntityBlockerType.PICKUP) {
  }
}

class Decoration extends AnimatedStationary {
  Decoration(String templateName, String frames, Level level, Vector3 pos, double rot, [EntityBlockerType blockerType = EntityBlockerType.NONE]) : super(templateName, frames, level, pos, rot, blockerType)  {
  }

  factory Decoration.blocking(String templateName, String frames, Level level, Vector3 pos, double rot) {
    Decoration result = new Decoration(templateName, frames, level, pos, rot, EntityBlockerType.BLOCKING);
    result.blockerType = EntityBlockerType.BLOCKING;
    return result;
  }
}

class Puff extends Entity {
  String frames;
  int animStep = 0;
  double animAccum = 0.0;
  double speed = 1.0;
  
  Puff(String templateName, String frames, Level level, Vector3 pos, double rot) : super(level, pos, EntityBlockerType.NONE) {
    frames = frames.toUpperCase();
    this.frames = frames;
    spriteTemplate = spriteTemplates[templateName];
    this.pos = pos;
    this.rot = rot;
    speed = 1.0/((random.nextDouble()-0.5)*1.0+1.0);
    animFrame = FRAME_NAMES.indexOf(frames.substring(animStep, animStep+1));
    radius = 16.0;
  }
  
  void tick(double passedTime) {
    int lastAnimStep = animStep;
    animAccum+=passedTime*35.0/4.0*speed;
    animStep+=animAccum.floor();
    animAccum-=animAccum.floor();
    animStep = animStep;
    pos.y+=passedTime*32;
    Sector sector = level.bsp.findSector(pos.xz);
    if (pos.y>sector.ceilingHeight-4.0) pos.y=sector.ceilingHeight-4.0;
    if (lastAnimStep!=animStep) {
      if (animStep>=frames.length)
        remove();
      else 
        animFrame = FRAME_NAMES.indexOf(frames.substring(animStep, animStep+1));
    }
  }
}

class Blood extends Entity {
  String frames;
  int animStep = 0;
  double life = 0.0;
  double xa, ya, za;
  
  Blood(String templateName, String frames, Level level, Vector3 pos, double rot) : super(level, pos, EntityBlockerType.NONE) {
    // TODO: Base blood frame on damage amount.
    // Cutoffs are apparently 9 and 12
    frames = frames.toUpperCase();
    this.frames = frames;
    spriteTemplate = spriteTemplates[templateName];
    this.pos = pos;
    this.rot = rot;
    life = 0.2/((random.nextDouble()-0.5)*1.0+1.0);
    animStep = random.nextInt(frames.length);
    animFrame = FRAME_NAMES.indexOf(frames.substring(animStep, animStep+1));
    radius = 16.0;
    
    Vector3 spread;
    do {
      spread = new Vector3(random.nextDouble()-0.5, random.nextDouble()-0.5, random.nextDouble()-0.5)*2.0;
    } while (spread.length2>1.0);
    xa = spread.x; 
    ya = spread.y; 
    za = spread.z; 
  }
  
  void tick(double passedTime) {
    life-=passedTime;
    pos.y+=passedTime*ya*100.0;
    ya-=passedTime*5.0;
    Sector sector = level.bsp.findSector(pos.xz);
    if (pos.y<sector.floorHeight-4.0) pos.y=sector.floorHeight-4.0;
    if (life<0.0) {
      remove();
    }
  }
}

class Projectile extends Entity {
  Entity owner;
  Vector3 dir;
  
  Projectile(String templateName, Level level, Vector3 pos, this.dir, this.owner) : super(level, pos, EntityBlockerType.NONE) {
    spriteTemplate = spriteTemplates[templateName];
    radius = 8.0;
    height = 8.0;
    rot = atan2(dir.x, dir.z);
  }
  
  HashSet<Sector> sectorsInRange = new HashSet<Sector>();
  void tick(double passedTime) {
    sectorsInRange.clear();
    clipMove(dir,  passedTime, sectorsInRange);
    sectorsInRange.add(level.bsp.findSector(pos.xz));
    sectorsInRange.forEach((sector) {
      if (sector.floorHeight>pos.y) collided = true;
      if (sector.ceilingHeight<pos.y+height) collided = true;
    });
    pos.y+=dir.y*passedTime;
    
    if (collided) {
      remove();
    }
  }
  
  void clipMotionEntity(Entity e) {
    if (e!=owner) super.clipMotionEntity(e);
  }
}

class Mob extends Entity {
  Vector3 motion = new Vector3(0.0, 0.0, 0.0);
  double rotMotion = 0.9;
  double stepUp = 0.0;
  double walkTime = 0.0;
  
  
  Mob(Level level, Vector3 pos) : super(level, pos, EntityBlockerType.BLOCKING) {
    bleeds = true;
  }
  
  HashSet<Sector> sectorsInRange = new HashSet<Sector>();
//  List<SubSector> subSectorsInRange = new List<SubSector>();
  void move(double iX, double iY, double passedTime) {
    collided = false;
    animFrame=((walkTime*35/6)).floor()%4;
    Vector3 oldPos = new Vector3.copy(pos);
    
    rot+=rotMotion*passedTime;
    rotMotion *= pow(0.0000001, passedTime);
    
    stepUp *= pow(0.0000001, passedTime);
    double frictionXZ = pow(0.0005, passedTime);
    double frictionY = pow(0.2, passedTime);
    motion.x*=frictionXZ;
    motion.y*=frictionY;
    motion.z*=frictionXZ;
    motion.x+=(sin(rot)*iY-cos(rot)*iX)*passedTime*4000.0;
    motion.z+=(cos(rot)*iY+sin(rot)*iX)*passedTime*4000.0;
    sectorsInRange.clear();

    if (motion.xz.length2<100.0) {
      motion.x = 0.0;
      motion.z = 0.0;
    } else {
      walkTime+=passedTime;
      super.clipMove(motion, passedTime, sectorsInRange);
    }
    
    pos.y+=motion.y*(passedTime);


    if (blockerType==EntityBlockerType.BLOCKING) {
      BlockCell newBlockCell = level.blockmap.getBlockCell(pos.x, pos.z);
      if (blockCell!=newBlockCell) {
        if (blockCell!=null) blockCell.blockers.remove(this);
        blockCell = newBlockCell;
        if (blockCell!=null) blockCell.blockers.add(this);
      }
    } else if (blockerType==EntityBlockerType.PICKUP) {
      BlockCell newBlockCell = level.blockmap.getBlockCell(pos.x, pos.z);
      if (blockCell!=newBlockCell) {
        if (blockCell!=null) blockCell.pickups.remove(this);
        blockCell = newBlockCell;
        if (blockCell!=null) blockCell.pickups.add(this);
      }
    }


    double floorHeight = -10000000.0;
    sectorsInRange.add(level.bsp.findSector(pos.xz));
    sectorsInRange.forEach((sector) {
      if (sector.floorHeight>floorHeight) floorHeight=sector.floorHeight;
    });
    motion = (pos-oldPos)/passedTime;
    if (pos.y<=floorHeight.toDouble()) {
      if (oldPos.y<=floorHeight.toDouble()) {
        stepUp+=floorHeight-oldPos.y;
      }
      pos.y = floorHeight.toDouble();
      motion.y = 0.0;
    } else {
      motion.y-=2000*passedTime;
    }
    
    if (stepUp>32.0) stepUp = 32.0;

    inSubSectors.clear();
    level.bsp.findSubSectorsInRadius(pos.x, pos.z, radius*0.0, inSubSectors);
  }
  
}

class Player extends Mob {
  Fists fists = new Fists();
  Chainsaw chainsaw = new Chainsaw();
  Pistol pistol = new Pistol();
  Shotgun shotgun = new Shotgun();
  SuperShotgun superShotgun = new SuperShotgun();
  Chaingun chaingun = new Chaingun();
  RocketLauncher rocketLauncher = new RocketLauncher();
  Plasmagun plasmaGun = new Plasmagun();
  BFG bfg = new BFG();
  
  Weapon weapon;
  Weapon nextWeapon;
  double bobSpeed = 0.0, bobPhase = 0.0;

  Player(Level level, Vector3 pos, double rot) : super(level, pos) {
    this.rot = rot;
    radius = 16.0;
    nextWeapon = weapon = pistol;
  }
  
  void requestWeaponSlot(int slot) {
    Weapon switchTo = null;
    if (slot==0) switchTo = nextWeapon == fists?chainsaw:fists;
    if (slot==1) switchTo = pistol;
    if (slot==2) switchTo = nextWeapon == shotgun?superShotgun:shotgun;
    if (slot==3) switchTo = chaingun;
    if (slot==4) switchTo = rocketLauncher;
    if (slot==5) switchTo = plasmaGun;
    if (slot==6) switchTo = bfg;
    nextWeapon = switchTo;
  }
  
  void move(double iX, double iY, double passedTime) {
    super.move(iX,  iY,  passedTime);
    bobSpeed = motion.length/300.0;
    bobSpeed = bobSpeed*bobSpeed;
    if (bobSpeed>1.0) bobSpeed = 1.0;
    bobPhase+=passedTime*PI*2*1.5*bobSpeed;
  }
}

class Monster extends Mob {
  double turnIn = 0.0;
  double collideTime = 0.0;
  double rota = 0.0;
  double standStillTime = 0.0;
  
  Monster(String templateName, Level level, Vector3 pos, double rot, [bool transparent = false]) : super(level, pos) {
    spriteTemplate = spriteTemplates[templateName];
    this.pos = pos;
    this.rot = rot;
    this.transparent = transparent;
    this.shouldAimAt = true;
    
    radius = 16.0;
  }
  
  void tick(double passedTime) {
    if (standStillTime>0.0) {
      standStillTime-=passedTime;
      move(0.0, 0.0*0.0, passedTime);
    } else {
      move(0.0, 1.0*0.2, passedTime);
    }
    rot+=passedTime*rota;
    
    if (collided && collideTime<=0.0) {
      collideTime = random.nextDouble()*0.1+0.1;
      rota += (random.nextDouble()*4.0+2.0)*(random.nextInt(2)*2-1);
    }

    if (turnIn>0.0) {
      turnIn-=passedTime;
    }
    
    if (collideTime>0.0) {
      collideTime-=passedTime;
    } else {
      rota*=pow(0.000001, passedTime);
      if (turnIn<=0.0) {
        if (random.nextInt(3)==0) {
          standStillTime = random.nextDouble()*1.0+0.5; 
          turnIn = random.nextDouble()*2.0+0.5;
        } else {
          turnIn = random.nextDouble()*2.0+0.5;
          rota += (random.nextDouble()*30.0)*(random.nextInt(2)*2-1);
        }
      }
    }
  }
}