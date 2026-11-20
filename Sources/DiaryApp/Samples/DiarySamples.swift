import DiaryCore
import Foundation

enum DiarySamples {
    static func documents() -> [DiaryDocument] {
        [
            sample(
                title: "寻常的一天",
                markdown: """
                    ## 给今天留一点空白

                    早上泡了一杯茶，坐在窗边看了会儿树。风很轻，光从叶子之间落下来。

                    有些日子没有发生什么特别的事，但也值得被记住。

                    > 慢一点，才看得见生活里的细节。

                    ### 今天的小事

                    - 散步的时候，发现了一条没有走过的小路
                    - 读完了一篇很喜欢的文章
                    - 给自己留了半小时，什么也没安排

                    **想记住的瞬间**：回家的路上，天边那一小片温柔的颜色。

                    ---

                    这是合成示例，保存在独立示例库中，不会混入你的本地日记。
                    """),
            sample(
                title: "试试 Markdown",
                markdown: """
                    ## 让文字自然呈现

                    试着输入 **粗体**、*斜体* 和 `行内代码`。将光标移入文字，可以查看原始标记。

                    ### 一张小清单

                    - [x] 给今天写一个标题
                    - [ ] 写下一个值得记住的瞬间
                    - [ ] 留一句话给明天的自己

                    ### 也可以放一张表格

                    | 时间 | 记录 |
                    | --- | --- |
                    | 上午 | 安静地读书 |
                    | 傍晚 | 出门散步 |

                    ```swift
                    let today = "值得记住的一天"
                    ```

                    [Markdown 语法参考](https://commonmark.org/help/)
                    """),
            sample(
                title: "一篇私密的记录",
                markdown: """
                    ## 留给自己

                    有些想法，只需要被自己看见。

                    点击右上角的锁，为这篇示例设置密码。加密后，标题依然可见，正文会变成模糊的占位内容。

                    这是合成内容，可以在独立示例库中验证加密和重开恢复。
                    """),
        ]
    }
    private static func sample(title: String, markdown: String) -> DiaryDocument {
        DiaryDocument(
            metadata: DiaryMetadata(title: title), content: .plain(DiaryPayload(markdown: markdown)))
    }
}
