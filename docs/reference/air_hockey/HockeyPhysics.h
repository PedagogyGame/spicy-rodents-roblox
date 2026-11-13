#pragma once
// Engine-independent, deterministic 2-D air hockey. SI units (metres, seconds).
#include <algorithm>
#include <array>
#include <cmath>

namespace Aer {
struct V2 {
    double x=0,y=0;
    V2()=default; V2(double X,double Y):x(X),y(Y){}
    V2 operator+(V2 b)const{return {x+b.x,y+b.y};}
    V2 operator-(V2 b)const{return {x-b.x,y-b.y};}
    V2 operator*(double s)const{return {x*s,y*s};}
    V2 operator/(double s)const{return {x/s,y/s};}
    V2& operator+=(V2 b){x+=b.x;y+=b.y;return *this;}
};
inline double Dot(V2 a,V2 b){return a.x*b.x+a.y*b.y;}
inline double Length(V2 a){return std::sqrt(Dot(a,a));}
inline V2 Limit(V2 a,double max){double n=Length(a);return n>max?a*(max/n):a;}
inline double Clamp(double v,double a,double b){return std::max(a,std::min(b,v));}
struct Paddle {V2 p,target,v;};
struct Hit {double t; V2 normal,surface; int kind;};
struct Game {
    static constexpr double Step=1.0/240.0;
    static constexpr double HalfWidth=.62, HalfLength=1.17, Goal=.22;
    static constexpr double PuckRadius=.032, PaddleRadius=.064, PostRadius=.012;
    V2 puck,velocity;
    std::array<Paddle,2> paddles;
    std::array<int,2> score{{0,0}};
    double countdown=1.25,drag=.08,restitution=.95,maxSpeed=7.5;
    double difficulty=1.0;
    int winner=-1,serveSide=0,lastGoal=-1,hitSerial=0,goalSerial=0;
    bool paused=false;
    Game(){Reset();}
    void Reset(){
        score={{0,0}};winner=-1;paused=false;serveSide=0;lastGoal=-1;
        for(int i=0;i<2;i++)paddles[i]={{0,i? .80:-.80},{0,i? .80:-.80},{0,0}};
        ResetPuck();
    }
    void ResetPuck(){puck={0,serveSide? .30:-.30};velocity={0,0};countdown=1.25;}
    void Serve(){if(winner<0){countdown=0;velocity={(goalSerial%2?-.34:.34),serveSide?-1.25:1.25};}}
    void SetTarget(int side,V2 p){
        paddles[side].target={Clamp(p.x,-HalfWidth+PaddleRadius,HalfWidth-PaddleRadius),
          side?Clamp(p.y,PaddleRadius,HalfLength-PaddleRadius):Clamp(p.y,-HalfLength+PaddleRadius,-PaddleRadius)};
    }
    static double Fold(double x,double bound){
        double span=4*bound;double v=std::fmod(x+bound,span);if(v<0)v+=span;
        return v<=2*bound?v-bound:3*bound-v;
    }
    void AI(int side){
        double s=side?1:-1;auto& m=paddles[side];
        V2 target{puck.x*.65,s*.85};
        if(velocity.y*s>.05){
            double t=Clamp((s*.88-puck.y)/velocity.y,0,1.4);
            target={Fold(puck.x+velocity.x*t,HalfWidth-PuckRadius),s*.88};
        }
        if(puck.y*s>.08 && puck.y*s<1.07){
            // Get behind the puck, then commit through it toward the opposing goal.
            target={puck.x,puck.y+s*.115};
            if(std::abs(m.p.x-puck.x)<.065 && (m.p.y-puck.y)*s>.025)
                target={puck.x*.78,puck.y-s*.26};
        }
        if(countdown>0)target={0,s*.80};
        SetTarget(side,target);
    }
    static bool CircleTOI(V2 q,V2 relative,double r,double horizon,double& t){
        double a=Dot(relative,relative),b=Dot(q,relative),c=Dot(q,q)-r*r;
        if(c<=1e-10){if(b< -1e-9){t=0;return true;}return false;}
        if(a<1e-12 || b>=0)return false;
        double d=b*b-a*c;if(d<0)return false;
        t=(-b-std::sqrt(d))/a;
        return t>=-1e-9 && t<=horizon;
    }
    void Tick(double dt=Step,int human=0,bool computer=true){
        if(paused||winner>=0)return;
        if(computer)AI(1-human);
        std::array<V2,2> start;
        for(int i=0;i<2;i++){
            start[i]=paddles[i].p;
            const double speed=(i==human||!computer)?3.5:2.1*difficulty;
            V2 delta=Limit(paddles[i].target-paddles[i].p,speed*dt);
            paddles[i].v=delta/dt;
        }
        if(countdown>0){
            for(int i=0;i<2;i++)paddles[i].p+=paddles[i].v*dt;
            countdown-=dt;if(countdown<=0)Serve();return;
        }
        velocity=velocity*std::exp(-drag*dt);
        double left=dt,elapsed=0;
        for(int iteration=0;iteration<16&&left>1e-9;iteration++){
            Hit hit{left+1,{0,0},{0,0},-1};
            auto plane=[&](double t,V2 n,int kind){
                if(t>=-1e-9&&t<=left&&t<hit.t)hit={std::max(0.0,t),n,{0,0},kind};
            };
            for(int s:{-1,1}){
                if(velocity.x*s>1e-9){
                    plane((s*(HalfWidth-PuckRadius)-puck.x)/velocity.x,{-double(s),0},0);
                    double t=(s*(Goal-PuckRadius)-puck.x)/velocity.x;
                    if(std::abs(puck.y+velocity.y*t)>=HalfLength)
                        plane(t,{-double(s),0},0);
                }
                if(velocity.y*s>1e-9){
                    double t=(s*(HalfLength-PuckRadius)-puck.y)/velocity.y;
                    double x=puck.x+velocity.x*t;
                    if(std::abs(x)>=Goal)plane(t,{0,-double(s)},0);
                    // A full-puck crossing deep inside the goal awards exactly one point.
                    plane((s*(1.245+PuckRadius)-puck.y)/velocity.y,{0,0},s>0?3:4);
                }
            }
            auto circle=[&](V2 centre,V2 motion,double radius,int kind){
                double t;
                if(CircleTOI(puck-centre,velocity-motion,radius,left,t)&&t<hit.t){
                    V2 q=puck+velocity*t-(centre+motion*t);double len=Length(q);
                    hit={std::max(0.0,t),len>1e-9?q/len:V2{0,1},motion,kind};
                }
            };
            for(int sx:{-1,1})for(int sy:{-1,1})
                circle({sx*Goal,sy*HalfLength},{0,0},PuckRadius+PostRadius,0);
            for(int i=0;i<2;i++)circle(start[i]+paddles[i].v*elapsed,paddles[i].v,PuckRadius+PaddleRadius,1);
            if(hit.kind<0){puck+=velocity*left;elapsed+=left;left=0;break;}
            puck+=velocity*hit.t;elapsed+=hit.t;left-=hit.t;
            if(hit.kind==3||hit.kind==4){
                int scorer=hit.kind==3?0:1;score[scorer]++;lastGoal=scorer;goalSerial++;
                serveSide=1-scorer;
                if(score[scorer]>=7){winner=scorer;velocity={0,0};}
                else ResetPuck();
                break;
            }
            double vn=Dot(velocity-hit.surface,hit.normal);
            if(vn<0){velocity+=hit.normal*(-(1+(hit.kind==1?.94:restitution))*vn);hitSerial++;}
            velocity=Limit(velocity,maxSpeed);
            puck+=hit.normal*1e-6;
            // Progress even when two contacts share exactly the same instant.
            if(hit.t<1e-8){double e=std::min(left,1e-7);puck+=velocity*e;left-=e;elapsed+=e;}
        }
        for(int i=0;i<2;i++)paddles[i].p=start[i]+paddles[i].v*dt;
    }
};
} // namespace Aer
