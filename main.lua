
local screen = "menu"

local player = {}
local enemy = {}

local ground = 0
local winner = ""

local controls = {left=false,right=false}
local activeTouches = {}

-- =================================
-- FIGHTERS
-- =================================

local fighters = {
    {
        name="BLAZE",
        color={1,0.18,0.08},
        damage=15,
        speed=250,
        special="FIRE BLAST"
    },
    {
        name="VOLT",
        color={0.1,0.45,1},
        damage=14,
        speed=275,
        special="LIGHTNING STRIKE"
    },
    {
        name="SHADOW",
        color={0.65,0.2,1},
        damage=18,
        speed=235,
        special="DARK WAVE"
    },
    {
        name="TITAN",
        color={0.1,0.85,0.35},
        damage=20,
        speed=215,
        special="EARTH SMASH"
    }
}

local selectedPlayer=1
local selectedEnemy=2

-- =================================
-- AUDIO SYSTEM
-- =================================

local audioSettings = {
    music=true,
    sfx=true,
    musicVolume=0.30,
    sfxVolume=0.65
}

local sounds={}
local musicSource=nil
local audioReady=false

local function makeTone(freq,duration,waveform)

    local rate=22050
    local count=math.floor(rate*duration)

    local data=love.sound.newSoundData(count,rate,16,1)

    for i=0,count-1 do

        local t=i/rate
        local envelope=math.max(0,1-t/duration)
        local value

        if waveform=="square" then
            value=math.sin(2*math.pi*freq*t)>=0 and 1 or -1
        elseif waveform=="saw" then
            value=2*((freq*t)%1)-1
        else
            value=math.sin(2*math.pi*freq*t)
        end

        data:setSample(i,value*envelope*0.30)
    end

    return love.audio.newSource(data,"static")
end

local function makeMusic()

    local rate=22050
    local duration=8
    local count=rate*duration

    local data=love.sound.newSoundData(count,rate,16,1)

    local notes={
        110,110,146.83,164.81,
        110,110,146.83,196,
        130.81,130.81,164.81,174.61,
        130.81,146.83,110,110
    }

    for i=0,count-1 do

        local t=i/rate
        local beat=math.floor(t/0.5)%#notes+1
        local freq=notes[beat]

        local melody=math.sin(2*math.pi*freq*t)
        local bass=math.sin(2*math.pi*freq*0.5*t)

        data:setSample(i,melody*0.18+bass*0.12)
    end

    musicSource=love.audio.newSource(data,"static")
    musicSource:setLooping(true)
    musicSource:setVolume(audioSettings.musicVolume)
end

local function initializeAudio()

    local ok=pcall(function()

        sounds.punch=makeTone(130,0.13,"square")
        sounds.kick=makeTone(85,0.18,"saw")
        sounds.jump=makeTone(420,0.16,"sine")
        sounds.special=makeTone(680,0.45,"saw")
        sounds.hit=makeTone(95,0.20,"square")
        sounds.victory=makeTone(520,0.65,"sine")

        makeMusic()
    end)

    audioReady=ok

    if not ok then
        sounds={}
        musicSource=nil
    end
end

local function playSFX(name)

    if not audioSettings.sfx then return end

    local source=sounds[name]
    if not source then return end

    pcall(function()
        source:stop()
        source:setVolume(audioSettings.sfxVolume)
        source:play()
    end)
end

local function updateMusic()

    if not musicSource then return end

    pcall(function()

        musicSource:setVolume(audioSettings.musicVolume)

        if audioSettings.music then
            if not musicSource:isPlaying() then
                musicSource:play()
            end
        else
            musicSource:pause()
        end
    end)
end

-- =================================
-- UTILITIES
-- =================================

local function clamp(v,a,b)
    return math.max(a,math.min(v,b))
end

local function resetControls()

    controls.left=false
    controls.right=false
    activeTouches={}
end

-- =================================
-- PARTICLE ENGINE
-- =================================

local effects={}
local screenShake=0
local victoryTimer=0

-- KNOCKOUT VARIABLES

local knockoutTimer=0
local knockoutFlash=0
local knockoutImpact=false
local knockoutSlow=1
local knockoutTextScale=0

local function spawnParticle(x,y,color,power)

    local angle=love.math.random()*math.pi*2
    local speed=love.math.random(power*0.35,power)

    local life=love.math.random(25,55)/100

    table.insert(effects,{
        x=x,
        y=y,
        vx=math.cos(angle)*speed,
        vy=math.sin(angle)*speed,
        life=life,
        maxLife=life,
        size=love.math.random(2,6),
        color={
            color[1],
            color[2],
            color[3]
        }
    })
end

local function createImpact(x,y,color)

    for i=1,18 do
        spawnParticle(x,y,color,220)
    end

    screenShake=math.max(screenShake,0.12)
end

local function createSpecialBurst(x,y,color)

    for i=1,35 do
        spawnParticle(x,y,color,330)
    end

    screenShake=math.max(screenShake,0.22)
end

local function createVictoryBurst(x,y,color)

    for i=1,70 do
        spawnParticle(x,y,color,300)
    end

    for i=1,35 do

        local particleColor={
            love.math.random(),
            love.math.random(),
            love.math.random()
        }

        spawnParticle(x,y,particleColor,250)
    end

    screenShake=0.18
end

-- =================================
-- KNOCKOUT PARTICLE BURST
-- =================================

local function createKnockoutBurst(x,y,color)

    for i=1,65 do
        spawnParticle(x,y,color,420)
    end

    for i=1,25 do

        spawnParticle(
            x,y,
            {1,0.25,0.08},
            300
        )
    end

    screenShake=0.65
    knockoutFlash=0.30
end

-- =================================
-- UPDATE EFFECTS
-- =================================

local function updateEffects(dt)

    screenShake=math.max(0,screenShake-dt*1.5)
    knockoutFlash=math.max(0,knockoutFlash-dt*1.5)

    for i=#effects,1,-1 do

        local p=effects[i]

        p.x=p.x+p.vx*dt
        p.y=p.y+p.vy*dt

        p.vy=p.vy+350*dt
        p.vx=p.vx*0.97

        p.life=p.life-dt

        if p.life<=0 then
            table.remove(effects,i)
        end
    end

    if screen=="victory" then
        victoryTimer=victoryTimer+dt
    end
end

local function drawEffects()

    for _,p in ipairs(effects) do

        local alpha=math.max(0,p.life/p.maxLife)

        love.graphics.setColor(
            p.color[1],
            p.color[2],
            p.color[3],
            alpha
        )

        love.graphics.circle(
            "fill",
            p.x,
            p.y,
            p.size*alpha
        )
    end

    love.graphics.setColor(1,1,1)
end

-- =================================
-- LOAD
-- =================================

function love.load()

    love.graphics.setDefaultFilter("nearest","nearest")

    initializeAudio()
    updateMusic()
end

-- =================================
-- START GAME
-- =================================

function startGame()

    local w,h=love.graphics.getDimensions()
    ground=h*0.78

    local p=fighters[selectedPlayer]
    local e=fighters[selectedEnemy]

    player={
        x=w*0.20,y=ground-75,
        w=45,h=75,
        speed=p.speed,
        damage=p.damage,
        color=p.color,
        name=p.name,
        specialName=p.special,
        jump=-500,
        vy=0,
        onGround=true,
        facing=1,
        health=100,
        energy=0,
        attacking=false,
        attackTimer=0,
        cooldown=0,
        hitFlash=0,
        animTime=0,
        state="idle",
        specialTimer=0,
        specialEffect=0,
        knockout=false,
        knockoutVX=0,
        knockoutVY=0,
        knockoutAngle=0,
        knockoutRotation=0
    }

    enemy={
        x=w*0.75,y=ground-75,
        w=45,h=75,
        speed=75,
        damage=8,
        color=e.color,
        name=e.name,
        specialName=e.special,
        health=100,
        energy=0,
        facing=-1,
        cooldown=0,
        hitFlash=0,
        attacking=false,
        attackTimer=0,
        animTime=0,
        state="idle",
        specialTimer=0,
        specialEffect=0,
        knockout=false,
        knockoutVX=0,
        knockoutVY=0,
        knockoutAngle=0,
        knockoutRotation=0
    }

    winner=""

    effects={}
    screenShake=0
    victoryTimer=0

    knockoutTimer=0
    knockoutFlash=0
    knockoutImpact=false
    knockoutSlow=1
    knockoutTextScale=0

    resetControls()
    screen="game"

    updateMusic()
end

-- =================================
-- CHARACTER SELECTION
-- =================================

function changeCharacter(side,direction)

    if side=="player" then

        selectedPlayer=selectedPlayer+direction

        if selectedPlayer>#fighters then selectedPlayer=1 end
        if selectedPlayer<1 then selectedPlayer=#fighters end

        if selectedPlayer==selectedEnemy then

            selectedPlayer=selectedPlayer+direction

            if selectedPlayer>#fighters then selectedPlayer=1 end
            if selectedPlayer<1 then selectedPlayer=#fighters end
        end

    else

        selectedEnemy=selectedEnemy+direction

        if selectedEnemy>#fighters then selectedEnemy=1 end
        if selectedEnemy<1 then selectedEnemy=#fighters end

        if selectedEnemy==selectedPlayer then

            selectedEnemy=selectedEnemy+direction

            if selectedEnemy>#fighters then selectedEnemy=1 end
            if selectedEnemy<1 then selectedEnemy=#fighters end
        end
    end
end

-- =================================
-- KNOCKOUT SYSTEM
-- =================================

local function triggerKnockout(loser,victor,winnerText)

    if screen~="game" then return end

    winner=winnerText

    loser.knockout=true
    loser.state="knockout"
    loser.attacking=false
    loser.attackTimer=0

    local direction=loser.x>victor.x and 1 or -1

    loser.knockoutVX=direction*430
    loser.knockoutVY=-460

    loser.knockoutRotation=direction*5
    loser.knockoutAngle=0

    knockoutTimer=0
    knockoutImpact=false
    knockoutFlash=0
    knockoutSlow=0.45
    knockoutTextScale=0

    screenShake=0.28

    resetControls()

    playSFX("victory")

    screen="knockout"
end

-- =================================
-- WINNER
-- =================================

function checkWinner()

    if screen~="game" then return end

    if enemy.health<=0 then

        triggerKnockout(
            enemy,
            player,
            "PLAYER 1 WINS!"
        )

    elseif player.health<=0 then

        triggerKnockout(
            player,
            enemy,
            "PLAYER 2 WINS!"
        )
    end
end

-- =================================
-- NORMAL ATTACK
-- =================================

function attack()

    if screen~="game" then return end
    if player.cooldown>0 then return end

    player.attacking=true
    player.attackTimer=0.28
    player.cooldown=0.5
    player.state="attack"

    playSFX("punch")

    local distance=math.abs(
        (player.x+player.w/2)-
        (enemy.x+enemy.w/2)
    )

    local direction=enemy.x>player.x and 1 or -1

    if distance<100 and player.facing==direction then

        enemy.health=math.max(
            0,enemy.health-player.damage
        )

        enemy.hitFlash=0.2
        enemy.state="hit"

        createImpact(
            enemy.x+enemy.w/2,
            enemy.y+enemy.h/2,
            player.color
        )

        playSFX("hit")

        player.energy=clamp(player.energy+20,0,100)
        enemy.energy=clamp(enemy.energy+10,0,100)
    end

    checkWinner()
end

-- =================================
-- SPECIAL ATTACK
-- =================================

function specialAttack(fighter,target)

    if screen~="game" then return end
    if fighter.energy<100 then return end
    if fighter.specialTimer>0 then return end

    fighter.energy=0
    fighter.specialTimer=2
    fighter.specialEffect=0.55
    fighter.state="special"

    createSpecialBurst(
        fighter.x+fighter.w/2,
        fighter.y+fighter.h/2,
        fighter.color
    )

    playSFX("special")

    local distance=math.abs(
        (fighter.x+fighter.w/2)-
        (target.x+target.w/2)
    )

    local direction=target.x>fighter.x and 1 or -1

    if fighter.facing==direction and distance<240 then

        target.health=math.max(
            0,target.health-30
        )

        target.hitFlash=0.35
        target.state="hit"

        createSpecialBurst(
            target.x+target.w/2,
            target.y+target.h/2,
            fighter.color
        )

        playSFX("hit")

        fighter.energy=clamp(fighter.energy+5,0,100)
    end

    checkWinner()
end

function playerSpecial()
    specialAttack(player,enemy)
end

-- =================================
-- ENEMY AI
-- =================================

function enemyAI(dt)

    if screen~="game" then return end

    local distance=math.abs(
        (player.x+player.w/2)-
        (enemy.x+enemy.w/2)
    )

    enemy.facing=player.x<enemy.x and -1 or 1

    enemy.energy=clamp(
        enemy.energy+dt*2,0,100
    )

    if enemy.energy>=100
       and distance<230
       and enemy.specialTimer<=0 then

        specialAttack(enemy,player)
        return
    end

    if distance>75 then

        enemy.x=enemy.x+
            enemy.facing*enemy.speed*dt

        enemy.state="walk"

    elseif enemy.cooldown<=0 then

        enemy.attacking=true
        enemy.attackTimer=0.28
        enemy.cooldown=1.2
        enemy.state="attack"

        player.health=math.max(
            0,player.health-enemy.damage
        )

        player.hitFlash=0.2

        createImpact(
            player.x+player.w/2,
            player.y+player.h/2,
            enemy.color
        )

        playSFX("hit")

        player.energy=clamp(player.energy+12,0,100)

        checkWinner()

    else

        enemy.state="idle"
    end
end

-- =================================
-- UPDATE KNOCKOUT ANIMATION
-- =================================

local function updateKnockout(dt)

    knockoutTimer=knockoutTimer+dt

    -- SLOW MOTION OPENING

    local slowProgress=clamp(knockoutTimer/0.7,0,1)

    knockoutSlow=0.45+slowProgress*0.55

    local step=dt*knockoutSlow

    -- TITLE ANIMATION

    knockoutTextScale=math.min(
        1.2,
        knockoutTextScale+dt*3
    )

    -- UPDATE FALLING FIGHTER

    local loser=nil

    if player.knockout then
        loser=player
    elseif enemy.knockout then
        loser=enemy
    end

    if loser then

        loser.x=loser.x+loser.knockoutVX*step
        loser.y=loser.y+loser.knockoutVY*step

        loser.knockoutVY=loser.knockoutVY+1100*step

        loser.knockoutVX=loser.knockoutVX*0.985

        loser.knockoutAngle=
            loser.knockoutAngle+
            loser.knockoutRotation*step

        -- GROUND IMPACT

        if loser.y+loser.h>=ground then

            loser.y=ground-loser.h

            if not knockoutImpact then

                knockoutImpact=true

                loser.knockoutVY=0
                loser.knockoutVX=0

                createKnockoutBurst(
                    loser.x+loser.w/2,
                    ground,
                    loser.color
                )
            end
        end

        -- KEEP FIGHTER INSIDE SCREEN

        local w=love.graphics.getWidth()

        loser.x=clamp(
            loser.x,-loser.w/2,w-loser.w/2
        )
    end

    updateEffects(dt)

    -- VICTORY TRANSITION

    if knockoutTimer>=2.15 then

        screen="victory"
        victoryTimer=0
        knockoutTextScale=0
    end
end

-- =================================
-- UPDATE
-- =================================

function love.update(dt)

    dt=math.min(dt,0.05)

    if screen=="knockout" then

        updateKnockout(dt)
        return
    end

    updateEffects(dt)

    if screen~="game" then return end

    player.animTime=player.animTime+dt
    enemy.animTime=enemy.animTime+dt

    local moving=false

    if controls.left then

        player.x=player.x-player.speed*dt
        player.facing=-1
        moving=true
    end

    if controls.right then

        player.x=player.x+player.speed*dt
        player.facing=1
        moving=true
    end

    -- GRAVITY

    player.vy=player.vy+1200*dt
    player.y=player.y+player.vy*dt

    if player.y+player.h>=ground then

        player.y=ground-player.h
        player.vy=0
        player.onGround=true

    else

        player.onGround=false
    end

    -- ANIMATION STATES

    if player.hitFlash>0 then
        player.state="hit"
    elseif player.specialEffect>0 then
        player.state="special"
    elseif player.attacking then
        player.state="attack"
    elseif not player.onGround then
        player.state="jump"
    elseif moving then
        player.state="walk"
    else
        player.state="idle"
    end

    -- BOUNDARIES

    local w=love.graphics.getWidth()

    player.x=clamp(player.x,0,w-player.w)
    enemy.x=clamp(enemy.x,0,w-enemy.w)

    -- TIMERS

    player.cooldown=math.max(0,player.cooldown-dt)
    enemy.cooldown=math.max(0,enemy.cooldown-dt)

    player.attackTimer=math.max(0,player.attackTimer-dt)
    enemy.attackTimer=math.max(0,enemy.attackTimer-dt)

    player.hitFlash=math.max(0,player.hitFlash-dt)
    enemy.hitFlash=math.max(0,enemy.hitFlash-dt)

    player.specialTimer=math.max(0,player.specialTimer-dt)
    enemy.specialTimer=math.max(0,enemy.specialTimer-dt)

    player.specialEffect=math.max(0,player.specialEffect-dt)
    enemy.specialEffect=math.max(0,enemy.specialEffect-dt)

    player.attacking=player.attackTimer>0
    enemy.attacking=enemy.attackTimer>0

    enemyAI(dt)
end

-- =================================
-- HEALTH BAR
-- =================================

function drawHealthBar(x,y,width,health)

    love.graphics.setColor(0.15,0.15,0.15)
    love.graphics.rectangle("fill",x,y,width,18)

    love.graphics.setColor(0.9,0.05,0.05)

    love.graphics.rectangle(
        "fill",x,y,width*(health/100),18
    )

    love.graphics.setColor(1,1,1)
    love.graphics.rectangle("line",x,y,width,18)
end

-- =================================
-- ENERGY BAR
-- =================================

function drawEnergyBar(x,y,width,energy)

    love.graphics.setColor(0.1,0.1,0.15)
    love.graphics.rectangle("fill",x,y,width,12)

    love.graphics.setColor(0.1,0.8,1)

    love.graphics.rectangle(
        "fill",x,y,width*(energy/100),12
    )

    love.graphics.setColor(1,1,1)
    love.graphics.rectangle("line",x,y,width,12)
end

-- =================================
-- BUTTONS
-- =================================

function drawButton(text,y)

    local w,h=love.graphics.getDimensions()

    love.graphics.setColor(0.7,0.08,0.08)

    love.graphics.rectangle(
        "fill",w*0.2,y,w*0.6,h*0.09,12
    )

    love.graphics.setColor(1,1,1)

    love.graphics.printf(
        text,0,y+10,w,"center"
    )
end

function drawControl(text,x,y,width)

    local h=love.graphics.getHeight()

    love.graphics.setColor(0.65,0.08,0.08)

    love.graphics.rectangle(
        "fill",x,y,width,h*0.10,10
    )

    love.graphics.setColor(1,1,1)

    love.graphics.printf(
        text,x,y+h*0.035,width,"center"
    )
end

-- =================================
-- CHARACTER PREVIEW
-- =================================

function drawPreview(index,cx,cy,scale)

    local f=fighters[index]

    love.graphics.setColor(0.12,0.12,0.18)
    love.graphics.circle("fill",cx,cy,43*scale)

    love.graphics.setColor(
        f.color[1],f.color[2],f.color[3]
    )

    love.graphics.circle(
        "fill",cx,cy-23*scale,12*scale
    )

    love.graphics.rectangle(
        "fill",cx-13*scale,cy-9*scale,
        26*scale,35*scale
    )

    love.graphics.rectangle(
        "fill",cx-25*scale,cy-5*scale,
        12*scale,27*scale
    )

    love.graphics.rectangle(
        "fill",cx+13*scale,cy-5*scale,
        12*scale,27*scale
    )

    love.graphics.rectangle(
        "fill",cx-12*scale,cy+25*scale,
        10*scale,23*scale
    )

    love.graphics.rectangle(
        "fill",cx+3*scale,cy+25*scale,
        10*scale,23*scale
    )

    love.graphics.setColor(1,1,1)
end

-- =================================
-- CHARACTER SELECTION
-- =================================

function drawSelection()

    local w,h=love.graphics.getDimensions()

    love.graphics.clear(0.035,0.035,0.08)

    love.graphics.setColor(1,0.2,0.1)

    love.graphics.printf(
        "SELECT YOUR FIGHTERS",
        0,h*0.04,w,"center"
    )

    local py=h*0.19
    local ph=h*0.57
    local pw=w*0.43

    local lx=w*0.04
    local rx=w*0.53

    love.graphics.setColor(0.12,0.16,0.25)
    love.graphics.rectangle("fill",lx,py,pw,ph,12)

    love.graphics.setColor(0.2,0.55,1)

    love.graphics.printf(
        "PLAYER 1",lx,py+8,pw,"center"
    )

    drawPreview(
        selectedPlayer,lx+pw/2,py+ph*0.52,1
    )

    love.graphics.setColor(1,1,1)

    love.graphics.printf(
        fighters[selectedPlayer].name,
        lx,py+ph*0.78,pw,"center"
    )

    love.graphics.setColor(0.25,0.12,0.15)
    love.graphics.rectangle("fill",rx,py,pw,ph,12)

    love.graphics.setColor(1,0.25,0.2)

    love.graphics.printf(
        "PLAYER 2 / CPU",rx,py+8,pw,"center"
    )

    drawPreview(
        selectedEnemy,rx+pw/2,py+ph*0.52,1
    )

    love.graphics.setColor(1,1,1)

    love.graphics.printf(
        fighters[selectedEnemy].name,
        rx,py+ph*0.78,pw,"center"
    )

    love.graphics.setColor(1,0.75,0.1)

    love.graphics.printf("<",lx+5,py+ph*0.45,35,"center")
    love.graphics.printf(">",lx+pw-40,py+ph*0.45,35,"center")
    love.graphics.printf("<",rx+5,py+ph*0.45,35,"center")
    love.graphics.printf(">",rx+pw-40,py+ph*0.45,35,"center")

    love.graphics.setColor(0.75,0.08,0.08)

    love.graphics.rectangle(
        "fill",w*0.25,h*0.82,w*0.5,h*0.12,12
    )

    love.graphics.setColor(1,1,1)

    love.graphics.printf(
        "FIGHT!",0,h*0.85,w,"center"
    )

    love.graphics.setColor(0.7,0.7,0.7)
    love.graphics.print("BACK",10,10)
end

-- =================================
-- FIGHTER DRAWING
-- =================================

function drawFighter(f)

    local t=f.animTime
    local bob=0
    local leg=math.sin(t*12)*5
    local arm=math.sin(t*12)*4

    local cx=f.x+f.w/2
    local cy=f.y

    if f.state=="idle" then

        bob=math.sin(t*3)*2
        leg=0

    elseif f.state=="jump" then

        bob=-3

    elseif f.state=="attack" then

        arm=12
    end

    cy=cy+bob

    -- KNOCKOUT ROTATION

    love.graphics.push()

    if f.knockout then

        love.graphics.translate(cx,cy+f.h/2)

        love.graphics.rotate(f.knockoutAngle)

        love.graphics.translate(-cx,-(cy+f.h/2))
    end

    -- SHADOW

    love.graphics.setColor(0,0,0,0.3)
    love.graphics.ellipse("fill",cx,ground+4,28,7)

    -- AURA

    local aura=0.5+math.sin(t*5)*0.15

    love.graphics.setColor(
        f.color[1],
        f.color[2],
        f.color[3],
        aura*0.22
    )

    love.graphics.circle(
        "fill",
        cx,
        cy+25,
        38+aura*5
    )

    -- SPECIAL EFFECT

    if f.specialEffect>0 and not f.knockout then

        local alpha=f.specialEffect/0.55
        local direction=f.facing

        love.graphics.setColor(
            f.color[1],f.color[2],f.color[3],alpha
        )

        local beamX=direction==1 and cx+15 or cx-155

        love.graphics.rectangle(
            "fill",beamX,cy+5,140,30
        )

        love.graphics.circle(
            "fill",
            direction==1 and cx+150 or cx-150,
            cy+20,20
        )

        love.graphics.setColor(1,1,1,alpha)
        love.graphics.circle("line",cx,cy+20,38)
    end

    -- BODY

    if f.hitFlash>0 then

        love.graphics.setColor(1,1,1)

    else

        love.graphics.setColor(
            f.color[1],f.color[2],f.color[3]
        )
    end

    love.graphics.setLineWidth(9)

    love.graphics.line(
        cx-7,cy+48,cx-9+leg,cy+70
    )

    love.graphics.line(
        cx+7,cy+48,cx+9-leg,cy+70
    )

    love.graphics.rectangle(
        "fill",cx-13,cy+5,26,35,5
    )

    love.graphics.circle("fill",cx,cy-8,13)

    -- EYES

    love.graphics.setColor(0.05,0.05,0.08)

    love.graphics.circle(
        "fill",cx+f.facing*5,cy-10,2
    )

    -- ARMS

    if f.hitFlash>0 then

        love.graphics.setColor(1,1,1)

    else

        love.graphics.setColor(
            f.color[1],f.color[2],f.color[3]
        )
    end

    local frontX=cx+f.facing*13
    local backX=cx-f.facing*13

    if f.state=="attack" or f.state=="special" then

        love.graphics.setLineWidth(11)

        love.graphics.line(
            frontX,cy+15,
            frontX+f.facing*28,cy+20
        )

    else

        love.graphics.setLineWidth(9)

        love.graphics.line(
            frontX,cy+15,
            frontX+f.facing*8,cy+35+arm
        )

        love.graphics.line(
            backX,cy+15,
            backX-f.facing*8,cy+35-arm
        )
    end

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1,1,1)

    love.graphics.pop()
end

-- =================================
-- ARENA BACKGROUND
-- =================================

function drawStadiumBackground(w,h)

    local t=love.timer.getTime()

    love.graphics.setColor(0.025,0.025,0.09)
    love.graphics.rectangle("fill",0,0,w,h)

    love.graphics.setColor(0.06,0.07,0.18)

    love.graphics.rectangle(
        "fill",0,h*0.10,w,h*0.42
    )

    -- DISTANT LIGHTS

    for i=0,7 do

        local x=w*(i/7)

        love.graphics.setColor(0.12,0.13,0.28)

        love.graphics.rectangle(
            "fill",x-2,h*0.12,4,h*0.40
        )
    end

    -- AUDIENCE

    love.graphics.setColor(0.035,0.035,0.065)

    love.graphics.rectangle(
        "fill",0,h*0.32,w,h*0.23
    )

    for i=0,math.floor(w/12) do

        local x=i*12
        local offset=math.sin(i*2.3)*3

        love.graphics.setColor(0.10,0.11,0.19)

        love.graphics.circle(
            "fill",x,h*0.42+offset,4
        )

        love.graphics.rectangle(
            "fill",x-4,h*0.44+offset,8,14
        )
    end

    -- SPOTLIGHTS

    local beam1=w*0.27+math.sin(t*0.7)*w*0.08
    local beam2=w*0.73+math.sin(t*0.7+2)*w*0.08

    love.graphics.setColor(0.15,0.25,0.65,0.12)

    love.graphics.polygon(
        "fill",
        beam1-12,0,
        beam1+12,0,
        beam1+w*0.19,h*0.57,
        beam1-w*0.19,h*0.57
    )

    love.graphics.setColor(0.65,0.12,0.35,0.10)

    love.graphics.polygon(
        "fill",
        beam2-12,0,
        beam2+12,0,
        beam2+w*0.19,h*0.57,
        beam2-w*0.19,h*0.57
    )

    -- STADIUM LIGHTS

    for i=0,1 do

        local x=i==0 and w*0.18 or w*0.82

        love.graphics.setColor(0.25,0.3,0.55)

        love.graphics.rectangle(
            "fill",x-20,h*0.08,40,12,4
        )

        love.graphics.setColor(0.55,0.75,1,0.8)

        for j=0,3 do

            love.graphics.circle(
                "fill",x-13+j*9,h*0.085,3
            )
        end
    end

    -- PILLARS

    love.graphics.setColor(0.08,0.09,0.16)

    love.graphics.rectangle(
        "fill",0,h*0.27,w*0.055,h*0.50
    )

    love.graphics.rectangle(
        "fill",w*0.945,h*0.27,w*0.055,h*0.50
    )

    love.graphics.setColor(0.2,0.3,0.65)

    love.graphics.rectangle(
        "fill",w*0.045,h*0.27,w*0.01,h*0.50
    )

    love.graphics.rectangle(
        "fill",w*0.945,h*0.27,w*0.01,h*0.50
    )

    -- SIGNS

    love.graphics.setColor(0.45,0.05,0.08)

    love.graphics.rectangle(
        "fill",w*0.07,h*0.34,w*0.18,h*0.075,5
    )

    love.graphics.rectangle(
        "fill",w*0.75,h*0.34,w*0.18,h*0.075,5
    )

    love.graphics.setColor(1,0.35,0.2)

    love.graphics.printf(
        "FIGHT",w*0.07,h*0.36,w*0.18,"center"
    )

    love.graphics.printf(
        "ARENA",w*0.75,h*0.36,w*0.18,"center"
    )
end

function drawArenaFloor(w,h)

    local t=love.timer.getTime()

    love.graphics.setColor(0.09,0.10,0.16)

    love.graphics.rectangle(
        "fill",0,ground,w,h-ground
    )

    love.graphics.setColor(0.10,0.25,0.55,0.25)

    love.graphics.rectangle(
        "fill",0,ground,w,5
    )

    -- FLOOR GRID

    love.graphics.setColor(0.20,0.25,0.38,0.55)

    for i=0,10 do

        local x=w*i/10
        love.graphics.line(x,ground,x,h)
    end

    for i=1,5 do

        local y=ground+(h-ground)*i/5
        love.graphics.line(0,y,w,y)
    end

    -- CENTER PLATFORM

    love.graphics.setColor(0.13,0.15,0.25)

    love.graphics.rectangle(
        "fill",w*0.08,ground+8,w*0.84,h*0.15
    )

    love.graphics.setColor(0.8,0.12,0.16,0.8)

    love.graphics.rectangle(
        "fill",w*0.495,ground+8,w*0.01,h*0.15
    )

    love.graphics.setColor(0.8,0.12,0.15)

    love.graphics.rectangle(
        "fill",0,ground,w,3
    )

    local pulse=0.5+math.sin(t*2)*0.25

    love.graphics.setColor(0.15,0.35,0.9,pulse*0.15)

    love.graphics.ellipse(
        "fill",w/2,ground+25,w*0.28,13
    )

    love.graphics.setColor(0.9,0.15,0.1)

    love.graphics.circle(
        "fill",w*0.05,ground+5,4
    )

    love.graphics.circle(
        "fill",w*0.95,ground+5,4
    )
end

function drawArenaTitle(w,h)

    love.graphics.setColor(0.8,0.12,0.15,0.9)

    love.graphics.rectangle(
        "fill",w*0.36,h*0.17,w*0.28,h*0.065,6
    )

    love.graphics.setColor(1,1,1)

    love.graphics.printf(
        "FIGHTING ARENA",
        0,h*0.185,w,"center"
    )
end

function drawArena()

    local w,h=love.graphics.getDimensions()

    drawStadiumBackground(w,h)
    drawArenaFloor(w,h)
    drawArenaTitle(w,h)
end

-- =================================
-- GAME DRAWING
-- =================================

function drawGame()

    local w,h=love.graphics.getDimensions()

    love.graphics.clear(0.04,0.04,0.09)

    love.graphics.push()

    if screenShake>0 then

        local intensity=screenShake*45

        love.graphics.translate(
            (love.math.random()*2-1)*intensity,
            (love.math.random()*2-1)*intensity
        )
    end

    drawArena()

    drawFighter(player)
    drawFighter(enemy)

    drawEffects()

    love.graphics.pop()

    -- HUD

    drawHealthBar(
        w*0.05,h*0.05,w*0.35,player.health
    )

    drawHealthBar(
        w*0.60,h*0.05,w*0.35,enemy.health
    )

    drawEnergyBar(
        w*0.05,h*0.09,w*0.35,player.energy
    )

    drawEnergyBar(
        w*0.60,h*0.09,w*0.35,enemy.energy
    )

    love.graphics.setColor(1,1,1)

    love.graphics.print(
        player.name,w*0.05,h*0.02
    )

    love.graphics.print(
        enemy.name,w*0.60,h*0.02
    )

    -- MOBILE CONTROLS

    drawControl("LEFT",w*0.04,h*0.84,w*0.14)
    drawControl("RIGHT",w*0.20,h*0.84,w*0.14)
    drawControl("JUMP",w*0.57,h*0.84,w*0.13)
    drawControl("ATTACK",w*0.72,h*0.84,w*0.13)

    if player.energy>=100 then
        love.graphics.setColor(0.05,0.55,0.85)
    else
        love.graphics.setColor(0.22,0.22,0.28)
    end

    love.graphics.rectangle(
        "fill",w*0.86,h*0.84,w*0.13,h*0.10,10
    )

    love.graphics.setColor(1,1,1)

    love.graphics.printf(
        "SPECIAL",
        w*0.86,h*0.875,w*0.13,"center"
    )

    if player.energy>=100 then

        love.graphics.setColor(0.2,0.9,1)

        love.graphics.printf(
            "READY!",0,h*0.72,w,"center"
        )
    end
end

-- =================================
-- KNOCKOUT SCREEN DRAWING
-- =================================

function drawKnockout()

    local w,h=love.graphics.getDimensions()

    love.graphics.clear(0.025,0.015,0.035)

    -- ARENA SHAKE

    love.graphics.push()

    if screenShake>0 then

        local intensity=screenShake*35

        love.graphics.translate(
            (love.math.random()*2-1)*intensity,
            (love.math.random()*2-1)*intensity
        )
    end

    drawArena()

    drawFighter(player)
    drawFighter(enemy)

    drawEffects()

    love.graphics.pop()

    -- RED IMPACT FLASH

    if knockoutFlash>0 then

        love.graphics.setColor(
            1,0.03,0.02,knockoutFlash
        )

        love.graphics.rectangle(
            "fill",0,0,w,h
        )
    end

    -- DARK OVERLAY

    local fade=clamp(knockoutTimer*0.35,0,0.38)

    love.graphics.setColor(0,0,0,fade)

    love.graphics.rectangle(
        "fill",0,0,w,h
    )

    -- KNOCKOUT TEXT

    local scale=math.min(1,knockoutTextScale)

    local pulse=1+math.sin(knockoutTimer*9)*0.045

    love.graphics.push()

    love.graphics.translate(w/2,h*0.28)

    love.graphics.scale(scale*pulse,scale*pulse)

    love.graphics.setColor(0.35,0.01,0.01,0.9)

    love.graphics.printf(
        "KNOCKOUT!",
        -w/2+5,5,w,"center"
    )

    love.graphics.setColor(1,0.12,0.06)

    love.graphics.printf(
        "KNOCKOUT!",
        -w/2,0,w,"center"
    )

    love.graphics.setColor(1,0.85,0.3)

    love.graphics.rectangle(
        "fill",-w*0.27,48,w*0.54,3
    )

    love.graphics.pop()

    -- WINNER ANNOUNCEMENT

    if knockoutTimer>0.7 then

        local alpha=clamp((knockoutTimer-0.7)*2,0,1)

        love.graphics.setColor(1,1,1,alpha)

        love.graphics.printf(
            winner,
            0,h*0.42,w,"center"
        )
    end

    love.graphics.setColor(1,1,1)
end

-- =================================
-- SETTINGS SCREEN
-- =================================

function drawSettings()

    local w,h=love.graphics.getDimensions()

    love.graphics.clear(0.035,0.035,0.08)

    love.graphics.setColor(1,0.25,0.15)

    love.graphics.printf(
        "AUDIO SETTINGS",
        0,h*0.12,w,"center"
    )

    local function settingButton(label,y)

        love.graphics.setColor(0.13,0.16,0.25)

        love.graphics.rectangle(
            "fill",w*0.12,y,w*0.76,h*0.105,10
        )

        love.graphics.setColor(1,1,1)

        love.graphics.printf(
            label,0,y+h*0.03,w,"center"
        )
    end

    settingButton(
        "MUSIC: "..(audioSettings.music and "ON" or "OFF"),
        h*0.30
    )

    settingButton(
        "SOUND EFFECTS: "..(audioSettings.sfx and "ON" or "OFF"),
        h*0.44
    )

    settingButton(
        "MUSIC VOLUME: "..math.floor(audioSettings.musicVolume*100).."% (- / +)",
        h*0.58
    )

    settingButton(
        "SFX VOLUME: "..math.floor(audioSettings.sfxVolume*100).."% (- / +)",
        h*0.72
    )

    love.graphics.setColor(0.75,0.08,0.08)

    love.graphics.rectangle(
        "fill",w*0.30,h*0.86,w*0.40,h*0.08,8
    )

    love.graphics.setColor(1,1,1)

    love.graphics.printf(
        "BACK",0,h*0.88,w,"center"
    )
end

-- =================================
-- MAIN DRAW
-- =================================

function love.draw()

    local w,h=love.graphics.getDimensions()

    if screen=="menu" then

        love.graphics.clear(0.04,0.04,0.09)

        love.graphics.setColor(1,0.2,0.1)

        love.graphics.printf(
            "FIGHTING ARENA",
            0,h*0.16,w,"center"
        )

        drawButton("PLAY",h*0.40)
        drawButton("SETTINGS",h*0.53)
        drawButton("EXIT",h*0.66)

    elseif screen=="select" then

        drawSelection()

    elseif screen=="game" then

        drawGame()

    elseif screen=="knockout" then

        drawKnockout()

    elseif screen=="victory" then

        love.graphics.clear(0.04,0.04,0.09)

        love.graphics.push()

        local intensity=screenShake*45

        if screenShake>0 then

            love.graphics.translate(
                (love.math.random()*2-1)*intensity,
                (love.math.random()*2-1)*intensity
            )
        end

        drawEffects()

        love.graphics.pop()

        local pulse=1+math.sin(victoryTimer*5)*0.04

        love.graphics.push()

        love.graphics.translate(w/2,h*0.30)
        love.graphics.scale(pulse,pulse)

        love.graphics.setColor(1,0.8,0.1)

        love.graphics.printf(
            "KNOCKOUT!",
            -w/2,0,w,"center"
        )

        love.graphics.pop()

        love.graphics.setColor(1,1,1)

        love.graphics.printf(
            winner,0,h*0.40,w,"center"
        )

        drawButton("PLAY AGAIN",h*0.55)
        drawButton("MAIN MENU",h*0.68)

    elseif screen=="settings" then

        drawSettings()
    end
end

-- =================================
-- INPUT HANDLING
-- =================================

function handlePress(x,y)

    local w,h=love.graphics.getDimensions()

    if screen=="menu" then

        if y>h*0.40 and y<h*0.49 then

            screen="select"

        elseif y>h*0.53 and y<h*0.62 then

            screen="settings"

        elseif y>h*0.66 and y<h*0.75 then

            love.event.quit()
        end

    elseif screen=="select" then

        local py=h*0.19
        local ph=h*0.57
        local pw=w*0.43

        local lx=w*0.04
        local rx=w*0.53

        if x<75 and y<45 then

            screen="menu"

        elseif y>py and y<py+ph then

            if x>=lx and x<lx+pw then

                if x<lx+pw*0.30 then
                    changeCharacter("player",-1)
                elseif x>lx+pw*0.70 then
                    changeCharacter("player",1)
                end

            elseif x>=rx and x<rx+pw then

                if x<rx+pw*0.30 then
                    changeCharacter("enemy",-1)
                elseif x>rx+pw*0.70 then
                    changeCharacter("enemy",1)
                end
            end

        elseif y>h*0.82 and y<h*0.94 then

            startGame()
        end

    elseif screen=="settings" then

        if y>h*0.30 and y<h*0.405 then

            audioSettings.music=not audioSettings.music
            updateMusic()

        elseif y>h*0.44 and y<h*0.545 then

            audioSettings.sfx=not audioSettings.sfx

        elseif y>h*0.58 and y<h*0.685 then

            if x<w*0.5 then

                audioSettings.musicVolume=clamp(
                    audioSettings.musicVolume-0.1,0,1
                )

            else

                audioSettings.musicVolume=clamp(
                    audioSettings.musicVolume+0.1,0,1
                )
            end

            updateMusic()

        elseif y>h*0.72 and y<h*0.825 then

            if x<w*0.5 then

                audioSettings.sfxVolume=clamp(
                    audioSettings.sfxVolume-0.1,0,1
                )

            else

                audioSettings.sfxVolume=clamp(
                    audioSettings.sfxVolume+0.1,0,1
                )
            end

        else

            screen="menu"
        end

    elseif screen=="victory" then

        if y>h*0.55 and y<h*0.64 then

            screen="select"

        elseif y>h*0.68 and y<h*0.77 then

            screen="menu"
        end

    elseif screen=="game" and y>h*0.84 then

        if x<w*0.19 then

            controls.left=true

        elseif x<w*0.36 then

            controls.right=true

        elseif x>w*0.57 and x<w*0.71 then

            if player.onGround then

                player.vy=player.jump
                player.onGround=false

                playSFX("jump")
            end

        elseif x>w*0.71 and x<w*0.86 then

            attack()

        elseif x>=w*0.86 then

            playerSpecial()
        end
    end
end

-- =================================
-- TOUCH CONTROLS
-- =================================

function refreshControls()

    controls.left=false
    controls.right=false

    for _,action in pairs(activeTouches) do

        if action=="left" then
            controls.left=true

        elseif action=="right" then
            controls.right=true
        end
    end
end

function love.touchpressed(id,x,y)

    local w,h=love.graphics.getDimensions()

    handlePress(x,y)

    if screen=="game" and y>h*0.84 then

        if x<w*0.19 then

            activeTouches[id]="left"

        elseif x<w*0.36 then

            activeTouches[id]="right"
        end
    end

    refreshControls()
end

function love.touchreleased(id,x,y)

    activeTouches[id]=nil
    refreshControls()
end

-- =================================
-- MOUSE
-- =================================

function love.mousepressed(x,y,button)

    handlePress(x,y)
end

function love.mousereleased(x,y,button)

    controls.left=false
    controls.right=false
end

-- =================================
-- KEYBOARD
-- =================================

function love.keypressed(key)

    if screen=="select" then

        if key=="a" then

            changeCharacter("player",-1)

        elseif key=="d" then

            changeCharacter("player",1)

        elseif key=="left" then

            changeCharacter("enemy",-1)

        elseif key=="right" then

            changeCharacter("enemy",1)

        elseif key=="return" then

            startGame()
        end

    elseif key=="left" or key=="a" then

        controls.left=true

    elseif key=="right" or key=="d" then

        controls.right=true

    elseif key=="space" then

        if player.onGround and screen=="game" then

            player.vy=player.jump
            player.onGround=false

            playSFX("jump")
        end

    elseif key=="z" then

        attack()

    elseif key=="x" then

        playerSpecial()

    elseif key=="escape" then

        screen="menu"
        resetControls()
    end
end

function love.keyreleased(key)

    if key=="left" or key=="a" then
        controls.left=false
    end

    if key=="right" or key=="d" then
        controls.right=false
    end
end
