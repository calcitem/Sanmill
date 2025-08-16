import threading
import tkinter as tk
from tkinter import messagebox
from typing import List, Optional, Tuple


class GuiHumanPlayer:
    """基于 Tkinter 的人类玩家，通过鼠标点击完成走子/吃子/拿起放下。

    设计要点：
    - 每次 play(board) 时，根据当前局面生成合法走子集合，并阻塞等待用户点击完成一个合法走子。
    - period 0（落子）/period 3（吃子）：一次点击完成；
    - period 1/2（走子/飞子）：先点起始格（自己的子），再点目标格；可通过再次点击切换起始格。
    - 所有合法性由 game.getValidMoves + board.get_action_from_move 双重保证。
    """

    # GUI 需要实际棋盘，以固定颜色（先手白、后手黑）渲染
    requires_actual_board = True

    def __init__(self, game, board_size_px: int = 560, difficulty: float = 0.5):
        self.game = game
        self.board_size_px = int(board_size_px)
        self.cell_px = self.board_size_px // 7
        # 供 Arena 在 verbose 模式下读取，用于 AI 选择策略时的微调参数
        self.difficulty = float(difficulty)
        # 当前行动方（由 Arena 在每步调用前设置）
        self.current_player = 1
        # 画布边距用于坐标标注（对称设置以使棋盘居中于窗口）
        self.margin_left = int(self.cell_px * 1.0)
        self.margin_right = int(self.cell_px * 1.0)
        self.margin_top = int(self.cell_px * 0.9)
        self.margin_bottom = int(self.cell_px * 0.9)
        # 坐标标注字体大小（缩小为之前约 1/3）
        self.coord_font_size = max(10, int(self.cell_px * 0.23))

        # Tk 初始化
        try:
            self.root = tk.Tk()
        except Exception as ex:
            raise RuntimeError(f"Failed to initialize Tkinter GUI: {ex}")
        self.root.title("Sanmill - Human Player GUI")

        # 画布尺寸按左右/上下边距对称确定，使棋盘整体居中
        self.canvas_w = self.margin_left + self.board_size_px + self.margin_right
        self.canvas_h = self.margin_top + self.board_size_px + self.margin_bottom
        # 棋盘底色改为灰色
        self.canvas = tk.Canvas(self.root, width=self.canvas_w, height=self.canvas_h, bg="#cfcfcf")
        # 使用手型光标以提高可见性（具体大小受系统设置影响）
        try:
            self.canvas.configure(cursor="hand2")
        except Exception:
            pass
        self.canvas.pack()

        # 状态栏（显示双方角色与最近一步）
        self.status_var = tk.StringVar(value="")
        self.status_label = tk.Label(self.root, textvariable=self.status_var, anchor="w", justify="left", font=("Arial", 11))
        self.status_label.place(x=10, y=5)
        # 棋盘右上角最近一步覆盖文本
        self._last_move_canvas_id = None

        # 交互状态
        self.current_board = None
        self.legal_moves: List[List[int]] = []
        self.selected_src: Optional[Tuple[int, int]] = None
        self.pending_action: Optional[int] = None
        self._action_ready = tk.BooleanVar(value=False)
        self.closed = False

        # 图元缓存：节点坐标 -> 画布对象 id
        self.node_ovals = {}  # (x, y) -> oval_id
        # 人类方颜色：1=白，-1=黑（通过 set_roles 或首次 set_to_move 推断）
        self.human_color: Optional[int] = None
        # 中央预留的手中棋子数量文本 ID（placing 阶段显示）
        self._inhand_text_id: Optional[int] = None
        self.roles_text = ""    # "White: AI/Human | Black: AI/Human"
        self.last_move_text = "" # "Last: White(Human) a1-a4"
        # 不再显示思考中文本，仅保留最近一步

        # 绑定点击事件
        self.canvas.bind("<Button-1>", self._on_click)
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

        # 画静态棋盘连线
        self._draw_static_board()

        # 窗口启动后居中到主显示器
        self._center_window_on_primary()

        # 启动事件循环（非阻塞地）
        self._loop_thread = threading.Thread(target=self._tk_mainloop, daemon=True)
        self._loop_thread.start()

    def set_roles(self, white_role: str, black_role: str):
        self.roles_text = f"White: {white_role} | Black: {black_role}"
        try:
            # 记录人类方颜色，便于显示 placing 阶段的“手中棋子数”
            if isinstance(white_role, str) and white_role.lower() == 'human':
                self.human_color = 1
            elif isinstance(black_role, str) and black_role.lower() == 'human':
                self.human_color = -1
        except Exception:
            pass
        self._refresh_status()

    def set_last_move(self, side: str, role: str, notation: str):
        self.last_move_text = f"Last: {side}({role}) {notation}"
        self._refresh_status()
        # 在棋盘右上角覆盖显示最近一步（只标注颜色与走法）
        try:
            label = f"{side}: {notation}"
            # 放在画布右上角，紧贴右边缘留白 ~10px，与左上角状态文本同一高度
            x = self.canvas_w - 10
            try:
                self.root.update_idletasks()
                y = int(self.status_label.winfo_y())
            except Exception:
                y = 8
            if self._last_move_canvas_id is None:
                self._last_move_canvas_id = self.canvas.create_text(
                    x, y, text=label, fill="#222", anchor="ne", font=("Arial", 10, "bold")
                )
            else:
                self.canvas.itemconfig(self._last_move_canvas_id, text=label, font=("Arial", 10, "bold"))
                self.canvas.coords(self._last_move_canvas_id, x, y)
        except Exception:
            pass

    # 占位（兼容旧调用），不做任何显示
    def set_thinking(self, side: str, role: str):
        return

    def set_status_text(self, text: str):
        # 兼容旧接口：直接覆盖整段状态文本
        self.roles_text = text
        self.last_move_text = ""
        self._refresh_status()

    def _refresh_status(self):
        # 仅显示第一行（双方角色），不再显示第二行
        self.status_var.set(self.roles_text or "")

    # ---------------------------- Tk helpers ----------------------------
    def _tk_mainloop(self):
        try:
            self.root.mainloop()
        except Exception:
            pass

    def _on_close(self):
        # 标记关闭并唤醒等待中的主线程
        self.closed = True
        try:
            self._action_ready.set(True)
        except Exception:
            pass
        try:
            self.root.quit()
        except Exception:
            pass
        try:
            self.root.destroy()
        except Exception:
            pass

    def _center_window_on_primary(self):
        try:
            # 先计算实际内容尺寸
            self.root.update_idletasks()
            width = self.root.winfo_width()
            height = self.root.winfo_height()
            if width <= 1 or height <= 1:
                # 回退到预估尺寸
                width = int(self.canvas_w)
                height = int(self.canvas_h + 30)
            screen_w = self.root.winfo_screenwidth()
            screen_h = self.root.winfo_screenheight()
            x = max(0, (screen_w - width) // 2)
            y = max(0, (screen_h - height) // 2)
            self.root.geometry(f"{width}x{height}+{x}+{y}")
        except Exception:
            pass

    def _xy_to_canvas_center(self, x: int, y: int) -> Tuple[int, int]:
        cx = self.margin_left + x * self.cell_px + self.cell_px // 2
        cy = self.margin_top + y * self.cell_px + self.cell_px // 2
        return cx, cy

    def _nearest_cell(self, px: int, py: int) -> Optional[Tuple[int, int]]:
        # 转换为棋盘内坐标系
        lx = px - self.margin_left
        ly = py - self.margin_top
        if lx < 0 or ly < 0 or lx >= self.board_size_px or ly >= self.board_size_px:
            return None
        x = max(0, min(6, int(lx // self.cell_px)))
        y = max(0, min(6, int(ly // self.cell_px)))
        return x, y

    def _draw_static_board(self):
        # 画合法点与连线（按标准邻接）
        try:
            # 与 pit.py 一致，使用包内绝对导入路径（相对导入在脚本直接运行时会失败）
            from game.standard_rules import coord_to_xy, adjacent
            from game.GameLogic import Board
        except Exception as ex:
            raise RuntimeError(f"Failed to import standard_rules or Board: {ex}")

        # 先画连线（避免覆盖圆点）
        drawn = set()
        for c, neighs in adjacent.items():
            x, y = coord_to_xy[c]
            for n in neighs:
                nx, ny = coord_to_xy[n]
                key = tuple(sorted(((x, y), (nx, ny))))
                if key in drawn:
                    continue
                drawn.add(key)
                x0, y0 = self._xy_to_canvas_center(x, y)
                x1, y1 = self._xy_to_canvas_center(nx, ny)
                self.canvas.create_line(x0, y0, x1, y1, fill="#888", width=3)

        # 仅画连线，不再画空心圆节点；棋子将按需绘制
        # 保存棋子半径用于后续绘制（约 1/3 格距）
        self.node_radius = max(10, int(self.cell_px * 0.33))

        # 坐标标注：行号（7..1）与列字母（a..g）
        # 行号放在每行左侧靠中
        for y in range(7):
            text_y = self.margin_top + y * self.cell_px + self.cell_px // 2
            # 将行号靠近棋盘左侧一些，并增大字号
            self.canvas.create_text(self.margin_left * 0.9, text_y, text=str(7 - y), fill="#444",
                                     font=("Arial", self.coord_font_size))
        # 列字母放在底部
        letters = ["a", "b", "c", "d", "e", "f", "g"]
        # 将列字母靠近棋盘下侧一些，并增大字号
        base_y = self.margin_top + self.board_size_px + self.margin_bottom * 0.15
        for x in range(7):
            text_x = self.margin_left + x * self.cell_px + self.cell_px // 2
            self.canvas.create_text(text_x, base_y, text=letters[x], fill="#444",
                                     font=("Arial", self.coord_font_size))

    def _render_pieces(self, board):
        # 仅在有棋子的格点绘制圆形；空格点不绘制任何圆
        try:
            allowed = board.allowed_places
            pieces = board.pieces
        except Exception:
            allowed = None
            pieces = None

        current_piece_positions = set()
        for y in range(7):
            for x in range(7):
                try:
                    if allowed is not None and int(allowed[x][y]) != 1:
                        continue
                    p = 0 if pieces is None else int(pieces[x][y])
                except Exception:
                    p = 0
                if p != 0:
                    current_piece_positions.add((x, y))

        existing_positions = set(self.node_ovals.keys())

        # 删除已不存在棋子的圆
        for pos in existing_positions - current_piece_positions:
            oid = self.node_ovals.get(pos)
            if oid is not None:
                try:
                    self.canvas.delete(oid)
                except Exception:
                    pass
                self.node_ovals.pop(pos, None)

        # 更新现有棋子外观
        for pos in existing_positions & current_piece_positions:
            x, y = pos
            try:
                piece = int(pieces[x][y])
            except Exception:
                piece = 0
            fill = "#ffffff" if piece == 1 else "#000000"
            oid = self.node_ovals.get(pos)
            if oid is not None:
                self.canvas.itemconfig(oid, fill=fill, outline="#888", width=2)

        # 新增需要绘制的棋子
        for pos in current_piece_positions - existing_positions:
            x, y = pos
            try:
                piece = int(pieces[x][y])
            except Exception:
                piece = 0
            fill = "#ffffff" if piece == 1 else "#000000"
            cx, cy = self._xy_to_canvas_center(x, y)
            r = getattr(self, "node_radius", max(10, int(self.cell_px * 0.33)))
            oid = self.canvas.create_oval(cx - r, cy - r, cx + r, cy + r, outline="#888", fill=fill)
            self.node_ovals[(x, y)] = oid

        # 高亮选中的起点（若存在对应棋子）
        if self.selected_src is not None and self.selected_src in self.node_ovals:
            self.canvas.itemconfig(self.node_ovals[self.selected_src], width=4, outline="#e67e22")

        # 更新中央“手中棋子数”显示（仅 placing 阶段）
        self._update_inhand_text(board)

    def _update_inhand_text(self, board, override_count: Optional[int] = None):
        # placing 阶段：尚未全部落子（put_pieces < 18）
        try:
            placing_phase = int(getattr(board, 'put_pieces', 18)) < 18
        except Exception:
            placing_phase = False

        # 若不在 placing 阶段，移除文本
        if not placing_phase:
            if self._inhand_text_id is not None:
                try:
                    self.canvas.delete(self._inhand_text_id)
                except Exception:
                    pass
                self._inhand_text_id = None
            return

        # 计算人类方手中棋子数量
        count_text = None
        try:
            if self.human_color is None:
                # 若尚未由 set_roles 判定，则在首次 set_to_move 时补充
                pass
            else:
                base_count = int(board.pieces_in_hand_count(int(self.human_color)))
                count_val = base_count if override_count is None else int(max(0, override_count))
                count_text = str(count_val)
        except Exception:
            count_text = None

        # 未能确认则不显示
        if not count_text:
            if self._inhand_text_id is not None:
                try:
                    self.canvas.delete(self._inhand_text_id)
                except Exception:
                    pass
                self._inhand_text_id = None
            return

        # 在棋盘中心绘制/更新文本
        cx, cy = self._xy_to_canvas_center(3, 3)
        # 中央数字稍微小一些且不加粗
        font_size = max(14, int(self.cell_px * 0.5))
        if self._inhand_text_id is None:
            try:
                self._inhand_text_id = self.canvas.create_text(
                    cx, cy, text=count_text, fill="#444", anchor="c",
                    font=("Arial", font_size)
                )
            except Exception:
                self._inhand_text_id = None
        else:
            try:
                self.canvas.itemconfig(self._inhand_text_id, text=count_text, fill="#444", font=("Arial", font_size))
                self.canvas.coords(self._inhand_text_id, cx, cy)
            except Exception:
                pass

    # ---------------------------- Click logic ---------------------------
    def _collect_legal_moves(self, board) -> List[List[int]]:
        # 将合法动作映射为 move（长度 2 或 4）
        # 使用实际棋盘与当前行动方，保证 GUI 与固定颜色一致
        valids = self.game.getValidMoves(board, self.current_player)
        legal_moves: List[List[int]] = []
        for a, flag in enumerate(valids):
            if flag:
                mv = board.get_move_from_action(a)
                legal_moves.append(mv)
        # 合法性断言：非空
        assert len(legal_moves) > 0, "No legal moves available for human player"
        return legal_moves

    def _on_click(self, event):
        if self.closed:
            return
        if self.current_board is None or self.legal_moves is None:
            return
        cell = self._nearest_cell(event.x, event.y)
        if cell is None:
            return
        x, y = cell
        # 仅允许点击到合法棋点
        try:
            if int(self.current_board.allowed_places[x][y]) != 1:
                return
        except Exception:
            return

        # 根据期别决定是一次点击还是两次点击
        period = getattr(self.current_board, "period", 0)

        if period in (0, 3):
            # 期 0：落子；期 3：吃子。一次点击：匹配长度为 2 的合法 move
            for mv in self.legal_moves:
                if len(mv) == 2 and mv[0] == x and mv[1] == y:
                    action = self.current_board.get_action_from_move(mv)
                    self.pending_action = int(action)
                    self._action_ready.set(True)
                    return
            # 未匹配上，忽略
            return

        # 期 1/2：走子/飞子，需要两次点击（使用实际棋盘的当前行动方）
        if self.selected_src is None:
            # 第一次点击：选择“当前行动方”的棋子，同时必须是某个合法 move 的起点
            if self.current_board.pieces[x][y] != self.current_player:
                return
            has_src = any(len(mv) == 4 and mv[0] == x and mv[1] == y for mv in self.legal_moves)
            if has_src:
                self.selected_src = (x, y)
                self._render_pieces(self.current_board)
            return
        else:
            # 第二次点击：选择目的地
            sx, sy = self.selected_src
            for mv in self.legal_moves:
                if len(mv) == 4 and mv[0] == sx and mv[1] == sy and mv[2] == x and mv[3] == y:
                    action = self.current_board.get_action_from_move(mv)
                    self.pending_action = int(action)
                    self._action_ready.set(True)
                    self.selected_src = None
                    self._render_pieces(self.current_board)
                    return
            # 若点击了另一个可作为起点的己方子，则切换起点
            if self.current_board.pieces[x][y] == self.current_player and any(len(mv) == 4 and mv[0] == x and mv[1] == y for mv in self.legal_moves):
                self.selected_src = (x, y)
                self._render_pieces(self.current_board)

    # ---------------------------- Public API ----------------------------
    def play(self, board):
        # 更新当前局面与合法走子
        self.current_board = board
        self.selected_src = None
        self._action_ready.set(False)
        self.pending_action = None
        self.legal_moves = self._collect_legal_moves(board)

        # 重绘棋子
        self._render_pieces(board)

        # 阻塞直到用户完成一个合法走子
        # 注：Tk 事件循环在后台线程运行，这里等待变量被置为 True
        self.root.wait_variable(self._action_ready)

        # 如果窗口已关闭，抛出 KeyboardInterrupt 让上层流程优雅退出
        if self.closed:
            raise KeyboardInterrupt("GUI window closed by user")

        # 返回 pending_action（必须由点击逻辑设置）
        assert self.pending_action is not None, "GUI interaction failed to produce an action"
        # 额外：若处于 placing 阶段且当前落子方为 human，立即更新中间数字
        try:
            if getattr(board, 'put_pieces', 18) < 18 and self.human_color is not None and self.current_player == self.human_color:
                # human 刚刚落子，手中棋子应当减 1；注意 put_pieces 还未在上层更新前生效
                base_count = int(board.pieces_in_hand_count(int(self.human_color)))
                self._update_inhand_text(board, override_count=base_count - 1)
        except Exception:
            pass

        return int(self.pending_action)

    def render_board(self, board):
        # 立即刷新当前棋盘显示（用于对手落子后立刻更新）
        try:
            self.current_board = board
            self._render_pieces(board)
            try:
                self.root.update_idletasks()
            except Exception:
                pass
        except Exception:
            pass

    def ask_restart(self, result_text: str) -> bool:
        """弹框显示对局结果，返回是否重新开始。"""
        try:
            return bool(messagebox.askyesno("Game Over", f"{result_text}\n\nRestart?", parent=self.root))
        except Exception:
            # 如果弹框失败，默认不重开
            return False

    def set_to_move(self, player: int):
        # 由 Arena 在调用 play() 前设置当前行动方（1=先手白，-1=后手黑）
        assert player in (1, -1)
        self.current_player = int(player)
        # 若尚未识别人类方颜色，首次调用时记录
        if self.human_color is None:
            try:
                # GUI 玩家即人类玩家；其首次获得行动权时的颜色即人类方颜色
                self.human_color = int(player)
            except Exception:
                pass


