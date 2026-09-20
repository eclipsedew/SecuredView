"""Server list routes — public list + admin CRUD."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from database import get_db
from models import Account, Server
from schemas import ServerInfo, ServerPublic, ServerCreate, ServerUpdate
from auth import get_current_account, require_auth_or_admin
from datetime import datetime, timezone

router = APIRouter(prefix="/api/servers", tags=["servers"])


def _require_admin(auth=Depends(require_auth_or_admin)):
    if isinstance(auth, dict) and auth.get("is_admin"):
        return auth
    from fastapi import HTTPException
    raise HTTPException(status_code=403, detail="Admin access required")


def _server_to_public(s: Server) -> dict:
    return {
        "id": s.id, "name": s.name, "country": s.country,
        "country_code": s.country_code, "city": s.city,
        "latitude": s.latitude, "longitude": s.longitude,
        "tier": s.tier, "is_active": s.is_active,
        "speed_mbps": s.speed_mbps, "ping_ms": s.ping_ms,
    }


@router.get("/", response_model=list[ServerInfo])
def list_servers(
    tier: str = None,
    account: Account = Depends(get_current_account),
    db: Session = Depends(get_db),
):
    """List all active servers. Free users see only free servers."""
    query = db.query(Server).filter(Server.is_active == True)

    is_premium = False
    if account:
        exp = account.premium_expires_at
        if exp and exp.tzinfo is None:
            exp = exp.replace(tzinfo=timezone.utc)
        is_premium = account.is_premium and exp and exp > datetime.now(timezone.utc)

    if tier:
        query = query.filter(Server.tier == tier)
    elif not is_premium:
        query = query.filter(Server.tier == "free")

    servers = query.order_by(Server.country, Server.name).all()
    return servers


@router.get("/all", response_model=list[ServerPublic])
def list_all_servers_public(db: Session = Depends(get_db)):
    """Public endpoint: list all servers (no sensitive data, for map display)."""
    servers = db.query(Server).filter(Server.is_active == True).order_by(Server.country).all()
    return [_server_to_public(s) for s in servers]


@router.get("/{server_id}", response_model=ServerInfo)
def get_server(server_id: str, db: Session = Depends(get_db)):
    server = db.query(Server).filter(Server.id == server_id).first()
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")
    return server


@router.post("/", response_model=ServerInfo)
def create_server(
    req: ServerCreate,
    _=Depends(_require_admin),
    db: Session = Depends(get_db),
):
    """Admin: add a new server."""
    existing = db.query(Server).filter(Server.id == req.id).first()
    if existing:
        raise HTTPException(status_code=409, detail="Server ID already exists")
    server = Server(**req.model_dump())
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


@router.put("/{server_id}", response_model=ServerInfo)
def update_server(
    server_id: str,
    req: ServerUpdate,
    _=Depends(_require_admin),
    db: Session = Depends(get_db),
):
    """Admin: update a server."""
    server = db.query(Server).filter(Server.id == server_id).first()
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")
    for key, val in req.model_dump(exclude_unset=True).items():
        setattr(server, key, val)
    db.commit()
    db.refresh(server)
    return server


@router.delete("/{server_id}")
def delete_server(
    server_id: str,
    _=Depends(_require_admin),
    db: Session = Depends(get_db),
):
    """Admin: soft-delete a server."""
    server = db.query(Server).filter(Server.id == server_id).first()
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")
    server.is_active = False
    db.commit()
    return {"message": "Server deactivated"}
