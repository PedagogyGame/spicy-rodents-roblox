#include "../Unreal/Source/AerHockey/HockeyPhysics.h"
#include <cassert>
#include <iostream>
using namespace Aer;
void active(Game& g){g.countdown=0;g.drag=0;}
int main(){
    {Game g;active(g);g.puck={.58,0};g.velocity={7,0};g.Tick(.02,0,false);assert(g.velocity.x<0&&g.puck.x<Game::HalfWidth-Game::PuckRadius);}
    {Game g;active(g);g.puck={.40,1.10};g.velocity={0,7.5};g.Tick(.04,0,false);assert(g.velocity.y<0&&g.score[0]==0);}
    {Game g;active(g);g.puck={0,1.10};g.velocity={0,7.5};g.Tick(.04,0,false);assert(g.score[0]==1&&g.score[1]==0&&g.countdown>0);for(int i=0;i<50;i++)g.Tick();assert(g.score[0]==1);}
    {Game g;active(g);g.puck={.203,1.08};g.velocity={0,7.5};g.Tick(.03,0,false);assert(g.hitSerial>0&&g.score[0]==0);}
    {Game g;active(g);g.puck={0,1.20};g.velocity={7.4,.10};g.Tick(.05,0,false);assert(std::abs(g.puck.x)<=Game::Goal-Game::PuckRadius+.001&&g.score[0]==0);}
    {Game g;active(g);g.puck={0,-.60};g.velocity={0,-7.5};g.Tick(.03,0,false);assert(g.velocity.y>0&&g.hitSerial>0);}
    {Game g;active(g);g.puck={0,-.61};g.velocity={0,0};g.SetTarget(0,{0,-.40});for(int i=0;i<25;i++)g.Tick(Game::Step,0,false);assert(g.velocity.y>1&&g.puck.y>-.61);}
    {Game g;active(g);g.paused=true;g.velocity={4,3};V2 p=g.puck;g.Tick();assert(g.puck.x==p.x&&g.puck.y==p.y);}
    {Game g;active(g);g.score[0]=6;g.puck={0,1.26};g.velocity={0,5};g.Tick(.01,0,false);assert(g.winner==0&&g.score[0]==7);g.Reset();assert(g.winner==-1&&g.score[0]==0);}
    {Game g;g.SetTarget(0,{9,9});assert(g.paddles[0].target.x<.56&&g.paddles[0].target.y<0);g.SetTarget(1,{-9,-9});assert(g.paddles[1].target.y>0);}
    {Game g;for(int i=0;i<240*120;i++){
        g.AI(0);g.Tick(Game::Step,1,true);
        assert(std::isfinite(g.puck.x)&&std::isfinite(g.puck.y));
        assert(Length(g.velocity)<=g.maxSpeed+.001);
        assert(std::abs(g.puck.x)<.621);
        if(g.winner>=0)g.Reset();
    }}
    std::cout<<"PASS: rails, fast shots, goals, posts, goal channel, stationary and moving paddles, pause, match reset, bounds, 120s stability\n";
}
