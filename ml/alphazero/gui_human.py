import threading
import tkinter as tk
from typing import List, Optional, Tuple


class GuiHumanPlayer:
    """基于 Tkinter 的人类玩家，通过鼠标点击完成走子/吃子/拿起放下。

    设计要点：
    - 每次 play(board) 时，根据当前局面生成合法走子集合，并阻塞等待用户点击完成一个合法走子。
    - period 0（落子）/period 3（吃子）：一次点击完成；
    - period 1/2（走子/飞子）：先点起始格（自己的子），再点目标格；可通过再次点击切换起始格。
    - 所有合法性由 game.getValidMoves + board.get_action_from_move 双重保证。
    """

    def __init__(self, game, board_size_px: int = 560, difficulty: float = 0.5):
        self.game = game
        self.board_size_px = int(board_size_px)
        self.cell_px = self.board_size_px // 7
        # 供 Arena 在 verbose 模式下读取，用于 AI 选择策略时的微调参数
        self.difficulty = float(difficulty)
        # 画布边距用于坐标标注
        self.margin_left = int(self.cell_px * 1.0)
        self.margin_top = int(self.cell_px * 0.3)
        self.margin_right = int(self.cell_px * 0.2)
        self.margin_bottom = int(self.cell_px * 0.9)

        # Tk 初始化
        try:
            self.root = tk.Tk()
        except Exception as ex:
            raise RuntimeError(f"Failed to initialize Tkinter GUI: {ex}")
        self.root.title("Sanmill - Human Player GUI")

        canvas_w = self.margin_left + self.board_size_px + self.margin_right
        canvas_h = self.margin_top + self.board_size_px + self.margin_bottom
        self.canvas = tk.Canvas(self.root, width=canvas_w, height=canvas_h, bg="white")
        self.canvas.pack()

        # 状态栏（显示双方角色与最近一步）
        self.status_var = tk.StringVar(value="")
        self.status_label = tk.Label(self.root, textvariable=self.status_var, anchor="w", justify="left")
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
        self.roles_text = ""    # "White: AI/Human | Black: AI/Human"
        self.last_move_text = "" # "Last: White(Human) a1-a4"

        # 绑定点击事件
        self.canvas.bind("<Button-1>", self._on_click)
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

        # 画静态棋盘连线
        self._draw_static_board()

        # 启动事件循环（非阻塞地）
        self._loop_thread = threading.Thread(target=self._tk_mainloop, daemon=True)
        self._loop_thread.start()

    def set_roles(self, white_role: str, black_role: str):
        self.roles_text = f"White: {white_role} | Black: {black_role}"
        self._refresh_status()

    def set_last_move(self, side: str, role: str, notation: str):
        self.last_move_text = f"Last: {side}({role}) {notation}"
        self._refresh_status()
        # 在棋盘右上角覆盖显示最近一步（只标注颜色与走法）
        try:
            label = f"{side}: {notation}"
            x = self.margin_left + self.board_size_px - 8
            y = self.margin_top + 12
            if self._last_move_canvas_id is None:
                self._last_move_canvas_id = self.canvas.create_text(
                    x, y, text=label, fill="#222", anchor="ne", font=("TkDefaultFont", 10, "bold")
                )
            else:
                self.canvas.itemconfig(self._last_move_canvas_id, text=label)
                self.canvas.coords(self._last_move_canvas_id, x, y)
        except Exception:
            pass

    def set_status_text(self, text: str):
        # 兼容旧接口：直接覆盖整段状态文本
        self.roles_text = text
        self.last_move_text = ""
        self._refresh_status()

    def _refresh_status(self):
        content = self.roles_text
        if self.last_move_text:
            content = content + "\n" + self.last_move_text if content else self.last_move_text
        self.status_var.set(content)

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
                self.canvas.create_line(x0, y0, x1, y1, fill="#888", width=2)

        # 再画节点（只绘制合法点）
        r = max(6, self.cell_px // 6)
        for y in range(7):
            for x in range(7):
                try:
                    if int(Board.allowed_places[x][y]) != 1:
                        continue
                except Exception:
                    continue
                cx, cy = self._xy_to_canvas_center(x, y)
                oval = self.canvas.create_oval(cx - r, cy - r, cx + r, cy + r, outline="#444", fill="#eee")
                self.node_ovals[(x, y)] = oval

        # 坐标标注：行号（7..1）与列字母（a..g）
        # 行号放在每行左侧靠中
        for y in range(7):
            text_y = self.margin_top + y * self.cell_px + self.cell_px // 2
            self.canvas.create_text(self.margin_left * 0.4, text_y, text=str(7 - y), fill="#333")
        # 列字母放在底部
        letters = ["a", "b", "c", "d", "e", "f", "g"]
        base_y = self.margin_top + self.board_size_px + self.margin_bottom * 0.5
        for x in range(7):
            text_x = self.margin_left + x * self.cell_px + self.cell_px // 2
            self.canvas.create_text(text_x, base_y, text=letters[x], fill="#333")

    def _render_pieces(self, board):
        # 重绘所有节点颜色：
        #   空：#eee；白子：#f7d774；黑子：#5aa1f7
        for (x, y), oid in self.node_ovals.items():
            fill = "#eee"
            try:
                piece = board.pieces[x][y]
            except Exception:
                piece = 0
            if piece == 1:
                fill = "#f7d774"
            elif piece == -1:
                fill = "#5aa1f7"
            self.canvas.itemconfig(oid, fill=fill, width=2)

        # 高亮选中的起点
        if self.selected_src is not None and self.selected_src in self.node_ovals:
            self.canvas.itemconfig(self.node_ovals[self.selected_src], width=4, outline="#e67e22")

    # ---------------------------- Click logic ---------------------------
    def _collect_legal_moves(self, board) -> List[List[int]]:
        # 将合法动作映射为 move（长度 2 或 4）
        valids = self.game.getValidMoves(board, 1)
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

        # 期 1/2：走子/飞子，需要两次点击
        if self.selected_src is None:
            # 第一次点击：选择自己的子，同时必须是某个合法 move 的起点
            if self.current_board.pieces[x][y] != 1:
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
            if self.current_board.pieces[x][y] == 1 and any(len(mv) == 4 and mv[0] == x and mv[1] == y for mv in self.legal_moves):
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
        return int(self.pending_action)


